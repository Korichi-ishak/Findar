-- =====================================================================
-- Findar · 005 · Dossiers de visite, messagerie, offres, accords
-- Source de vérité : dossier_event (ajout seul). Les colonnes d'état du
-- dossier sont un cache recalculé par trigger. Qui doit confirmer chaque
-- étape (les deux, une partie, automatique) est réglé dans
-- ref_dossier_step.meta.policy : on peut assouplir la règle sans
-- migration.
-- =====================================================================

-- Disponibilités pour les visites (par organisation, éventuellement par annonce)
create table public.availability_rule (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organization(id) on delete cascade,
  listing_id uuid references public.listing(id) on delete cascade,
  weekday smallint not null check (weekday between 0 and 6),   -- 0 = dimanche
  starts time not null,
  ends time not null check (ends > starts),
  slot_minutes smallint not null default 30,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index availability_rule_org_idx on public.availability_rule (organization_id, weekday);

create table public.dossier (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listing(id),
  buyer_id uuid not null references auth.users(id),
  organization_id uuid not null references public.organization(id),   -- côté annonceur : l'organisation, pas un agent
  handled_by uuid references auth.users(id),                          -- membre qui a pris le dossier (boîte commune)
  current_step_code text not null default 'contact' references public.ref_dossier_step(code),
  state text not null default 'ouvert',            -- cache lisible : ouvert, attente_annonceur, visite_confirmee, questionnaire, reserve, clos…
  opened_at timestamptz not null default now(),
  last_activity_at timestamptz not null default now(),
  closed_at timestamptz,
  close_reason text,
  metadata jsonb not null default '{}'
);
create unique index dossier_open_uq on public.dossier (listing_id, buyer_id) where closed_at is null;
create index dossier_buyer_idx on public.dossier (buyer_id, last_activity_at desc);
create index dossier_org_idx on public.dossier (organization_id, last_activity_at desc);

create table public.dossier_event (
  id bigint generated always as identity primary key,
  dossier_id uuid not null references public.dossier(id) on delete cascade,
  step_code text not null references public.ref_dossier_step(code),
  kind text not null check (kind in ('proposed', 'confirmed', 'declined', 'countered', 'expired', 'cancelled', 'answered', 'reminder', 'note')),
  side text not null check (side in ('buyer', 'seller', 'findar', 'system')),
  actor_id uuid,
  payload jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index dossier_event_dossier_idx on public.dossier_event (dossier_id, id);
create trigger dossier_event_append_only before update or delete on public.dossier_event
  for each row execute function app.forbid_mutation();

-- Côté d'un utilisateur dans un dossier (déduit de la session, jamais du client).
create or replace function app.dossier_side(d uuid) returns text
language sql stable security definer set search_path = public as $$
  select case
    when exists (select 1 from public.dossier x where x.id = d and x.buyer_id = auth.uid()) then 'buyer'
    when exists (select 1 from public.dossier x where x.id = d and app.is_org_member(x.organization_id)) then 'seller'
    when app.is_staff() then 'findar'
    else null end
$$;

create or replace function app.dossier_event_defaults() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null then
    new.actor_id := auth.uid();
    new.side := coalesce(app.dossier_side(new.dossier_id), new.side);
  end if;
  return new;
end $$;
create trigger dossier_event_defaults before insert on public.dossier_event
  for each row execute function app.dossier_event_defaults();

create or replace function app.dossier_after_event() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.dossier set
    current_step_code = case when new.kind in ('confirmed', 'proposed', 'answered') then new.step_code else current_step_code end,
    last_activity_at = now()
  where id = new.dossier_id;
  update public.listing set last_activity_at = now()
  where id = (select listing_id from public.dossier where id = new.dossier_id);
  return new;
end $$;
create trigger dossier_event_after after insert on public.dossier_event
  for each row execute function app.dossier_after_event();

-- Visites : une visite n'est « confirmee » que si les deux côtés ont confirmé
-- (ou selon la règle de l'étape visite_confirmee).
create table public.visit (
  id uuid primary key default gen_random_uuid(),
  dossier_id uuid not null references public.dossier(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz,
  status text not null default 'proposee'
    check (status in ('proposee', 'confirmee', 'faite', 'non_venue', 'annulee', 'expiree')),
  proposed_by_side text not null check (proposed_by_side in ('buyer', 'seller')),
  buyer_confirmed_at timestamptz,
  seller_confirmed_at timestamptz,
  address_released_at timestamptz,                  -- adresse visible pour l'acheteur à partir de…
  expires_at timestamptz,
  cancelled_reason text,
  version int not null default 1,                   -- verrou optimiste (double clic, onglets)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index visit_dossier_idx on public.visit (dossier_id);
create index visit_starts_idx on public.visit (starts_at) where status in ('proposee', 'confirmee');
create trigger visit_touch before update on public.visit for each row execute function app.touch_updated_at();

-- Confirmer sa part d'une visite (idempotent, version attendue).
create or replace function public.confirm_visit(p_visit uuid, p_version int) returns public.visit
language plpgsql security definer set search_path = public as $$
declare v public.visit; s text; policy text;
begin
  select * into v from public.visit where id = p_visit for update;
  if v.id is null then raise exception 'Visite introuvable' using errcode = 'P0002'; end if;
  s := app.dossier_side(v.dossier_id);
  if s is null or s not in ('buyer', 'seller') then raise exception 'Accès refusé' using errcode = '42501'; end if;
  if v.version <> p_version then raise exception 'Visite modifiée entre-temps' using errcode = '40001'; end if;
  if v.status <> 'proposee' then return v; end if;
  if v.expires_at is not null and now() >= v.expires_at then
    update public.visit set status = 'expiree', version = version + 1 where id = p_visit returning * into v;
    return v;
  end if;
  if s = 'buyer' then v.buyer_confirmed_at := coalesce(v.buyer_confirmed_at, now());
  else v.seller_confirmed_at := coalesce(v.seller_confirmed_at, now()); end if;
  select meta->>'policy' into policy from public.ref_dossier_step where code = 'visite_confirmee';
  if (coalesce(policy, 'both') = 'both' and v.buyer_confirmed_at is not null and v.seller_confirmed_at is not null)
     or (policy = 'one') or (policy = 'auto') then
    v.status := 'confirmee';
    v.address_released_at := v.starts_at - make_interval(hours => app.setting_int('visit.address_release_hours_before', 24));
  end if;
  update public.visit set buyer_confirmed_at = v.buyer_confirmed_at, seller_confirmed_at = v.seller_confirmed_at,
         status = v.status, address_released_at = v.address_released_at, version = version + 1
   where id = p_visit returning * into v;
  insert into public.dossier_event (dossier_id, step_code, kind, side, payload)
  values (v.dossier_id, case when v.status = 'confirmee' then 'visite_confirmee' else 'visite_demandee' end, 'confirmed', s,
          jsonb_build_object('visit_id', v.id, 'starts_at', v.starts_at));
  return v;
end $$;

-- L'acheteur voit l'adresse exacte seulement à partir de address_released_at d'une visite confirmée.
create or replace function app.can_see_address(p_property uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.listing l
    where l.property_id = p_property and app.is_org_member(l.organization_id)
  ) or app.is_staff() or exists (
    select 1 from public.visit v
    join public.dossier d on d.id = v.dossier_id
    join public.listing l on l.id = d.listing_id
    where l.property_id = p_property and d.buyer_id = auth.uid()
      and v.status = 'confirmee' and v.address_released_at <= now()
      and now() <= v.starts_at + interval '1 day'
  )
$$;

-- Messagerie (texte seul ; la détection numéro / acompte se fait côté serveur avant insertion)
create table public.message (
  id uuid primary key default gen_random_uuid(),
  dossier_id uuid not null references public.dossier(id) on delete cascade,
  sender_id uuid references auth.users(id),
  side text not null check (side in ('buyer', 'seller', 'findar', 'system')),
  body text not null check (char_length(body) between 1 and 2000),
  flags text[] not null default '{}',               -- phone, money, external_contact…
  moderation_status text not null default 'ok' check (moderation_status in ('ok', 'en_moderation', 'masque')),
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index message_dossier_idx on public.message (dossier_id, created_at);
create index message_moderation_idx on public.message (moderation_status) where moderation_status <> 'ok';

create or replace function app.message_defaults() returns trigger
language plpgsql security definer set search_path = public as $$
declare s text;
begin
  if auth.uid() is not null then
    s := app.dossier_side(new.dossier_id);
    if s is null then raise exception 'Accès refusé' using errcode = '42501'; end if;
    new.sender_id := auth.uid();
    new.side := s;
  end if;
  if cardinality(new.flags) > 0 then new.moderation_status := 'en_moderation'; end if;
  update public.dossier set last_activity_at = now() where id = new.dossier_id;
  return new;
end $$;
create trigger message_defaults before insert on public.message for each row execute function app.message_defaults();

-- Questionnaire après visite (une réponse par côté et par tour)
create table public.questionnaire_answer (
  id uuid primary key default gen_random_uuid(),
  dossier_id uuid not null references public.dossier(id) on delete cascade,
  visit_id uuid references public.visit(id),
  side text not null check (side in ('buyer', 'seller')),
  answer_code text not null references public.ref_questionnaire_answer(code),
  reason_code text,
  note text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique (dossier_id, visit_id, side)
);

create table public.offer (
  id uuid primary key default gen_random_uuid(),
  dossier_id uuid not null references public.dossier(id) on delete cascade,
  amount_dzd bigint not null check (amount_dzd > 0),
  made_by_side text not null check (made_by_side in ('buyer', 'seller')),
  status text not null default 'proposee' check (status in ('proposee', 'acceptee', 'refusee', 'contre_offre', 'retiree')),
  parent_offer_id uuid references public.offer(id),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  decided_at timestamptz
);

-- Accord confirmé par un agent Findar (réservation, compromis, vente, location).
-- Le prix convenu reste privé : seules des moyennes (k ≥ 5) en sortent.
create table public.deal (
  id uuid primary key default gen_random_uuid(),
  dossier_id uuid not null references public.dossier(id),
  listing_id uuid not null references public.listing(id),
  stage text not null check (stage in ('reservation', 'compromis', 'vente', 'location', 'annule')),
  agreed_price_dzd bigint check (agreed_price_dzd > 0),
  confirmed_by uuid references auth.users(id),     -- agent Findar
  confirmed_at timestamptz not null default now(),
  next_call_at timestamptz,
  note text
);
create index deal_listing_idx on public.deal (listing_id, confirmed_at desc);

-- Appels de confirmation à passer par l'équipe Findar
create table public.confirmation_call (
  id uuid primary key default gen_random_uuid(),
  reason text not null check (reason in ('apres_visite', 'reservation', 'sans_reponse', 'contradiction', 'inactivite', 'autre')),
  dossier_id uuid references public.dossier(id) on delete cascade,
  listing_id uuid references public.listing(id) on delete cascade,
  due_at timestamptz not null,
  assigned_to uuid references auth.users(id),
  outcome text,
  outcome_note text,
  done_at timestamptz,
  created_at timestamptz not null default now()
);
create index confirmation_call_queue_idx on public.confirmation_call (due_at) where done_at is null;
