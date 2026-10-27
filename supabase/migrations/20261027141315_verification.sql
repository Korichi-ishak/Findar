-- =====================================================================
-- Findar · 004 · Vérification et visites 360°
-- Un dossier de vérification (verification_case) par annonce, organisation
-- ou programme. Les pièces sont supprimées dès la décision : on garde
-- seulement le résultat (type, agent, date, décision).
-- =====================================================================

create table public.verification_case (
  id uuid primary key default gen_random_uuid(),
  subject_type text not null check (subject_type in ('listing', 'organization', 'program')),
  listing_id uuid references public.listing(id) on delete cascade,
  organization_id uuid references public.organization(id) on delete cascade,
  program_id uuid references public.program(id) on delete cascade,
  status text not null default 'documents'
    check (status in ('documents', 'a_corriger', 'bien_a_verifier', 'bien_planifie', 'valide', 'refuse', 'annule')),
  method_code text references public.ref_verification_method(code),   -- visite_360 ou visio choisi par l'annonceur
  assigned_to uuid references auth.users(id),
  submitted_by uuid references auth.users(id),
  due_at timestamptz,                                -- SLA (réglage verification.documents_hours, jours ouvrés)
  decision_reason text,
  closed_at timestamptz,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (subject_type = 'listing' and listing_id is not null) or
    (subject_type = 'organization' and organization_id is not null) or
    (subject_type = 'program' and program_id is not null)
  )
);
create index verification_case_queue_idx on public.verification_case (status, due_at) where closed_at is null;
create index verification_case_listing_idx on public.verification_case (listing_id);
create trigger verification_case_touch before update on public.verification_case for each row execute function app.touch_updated_at();

create table public.verification_document (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references public.verification_case(id) on delete cascade,
  document_type_code text not null references public.ref_document_type(code),
  storage_path text,                                 -- vidé à la décision (fichier supprimé du stockage)
  uploaded_by uuid references auth.users(id),
  uploaded_at timestamptz not null default now(),
  decision text check (decision in ('conforme', 'a_corriger', 'refuse')),
  decision_note text,
  decided_by uuid references auth.users(id),
  decided_at timestamptz,
  purged_at timestamptz,
  check (decided_at is null or storage_path is null)  -- une pièce décidée n'est plus stockée
);
create index verification_document_case_idx on public.verification_document (case_id);

-- File de suppression des fichiers (traitée par une fonction serveur qui
-- supprime l'objet dans le stockage).
create table public.storage_purge_queue (
  id bigint generated always as identity primary key,
  bucket text not null,
  path text not null,
  reason text not null,
  queued_at timestamptz not null default now(),
  done_at timestamptz
);

create or replace function app.purge_document_on_decision() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.decision is not null and old.decision is null then
    if old.storage_path is not null then
      insert into public.storage_purge_queue (bucket, path, reason) values ('verification', old.storage_path, 'decision');
    end if;
    new.storage_path := null;
    new.purged_at := now();
    new.decided_at := coalesce(new.decided_at, now());
    new.decided_by := coalesce(new.decided_by, auth.uid());
  end if;
  return new;
end $$;
create trigger verification_document_purge before update on public.verification_document
  for each row execute function app.purge_document_on_decision();

-- Chaque contrôle du bien (visio, tournage 360°, appel) : journal en ajout seul.
create table public.verification_attempt (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references public.verification_case(id) on delete cascade,
  method_code text not null references public.ref_verification_method(code),
  agent_id uuid references auth.users(id),
  scheduled_at timestamptz,
  started_at timestamptz,
  ended_at timestamptz,
  outcome_code text references public.ref_verification_outcome(code),
  checklist jsonb not null default '{}',            -- {item_code: true/false} : la checklist évolue sans migration
  report text,
  captures jsonb not null default '[]',             -- chemins des captures du bien (gardées)
  facts_hash text,                                  -- faits de l'annonce au moment du contrôle
  meeting_url text,                                 -- lien Zoom
  created_at timestamptz not null default now()
);
create index verification_attempt_case_idx on public.verification_attempt (case_id, created_at);
create index verification_attempt_agenda_idx on public.verification_attempt (agent_id, scheduled_at);

-- Le vérificateur ne peut pas être l'auteur de l'annonce.
create or replace function app.check_verifier_not_author() returns trigger
language plpgsql security definer set search_path = public as $$
declare author uuid;
begin
  if new.agent_id is null then return new; end if;
  select l.created_by into author
  from public.verification_case c join public.listing l on l.id = c.listing_id
  where c.id = new.case_id;
  if author is not null and author = new.agent_id then
    raise exception 'Le vérificateur ne peut pas être l''auteur de l''annonce' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger verification_attempt_not_author before insert or update on public.verification_attempt
  for each row execute function app.check_verifier_not_author();

-- Visites 360° (tournées par l'équipe Findar, hébergées dans Simple Virtual Tour)
create table public.tour (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid references public.listing(id) on delete set null,
  program_id uuid references public.program(id) on delete set null,
  owner_organization_id uuid not null references public.organization(id),   -- la visite appartient à l'annonceur
  provider text not null default 'simple_virtual_tour',
  external_id text,
  public_url text,
  shot_at timestamptz,
  photographer_id uuid references auth.users(id),
  delivered_at timestamptz,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index tour_listing_idx on public.tour (listing_id);

create table public.photo_mission (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid references public.listing(id) on delete cascade,
  program_id uuid references public.program(id) on delete cascade,
  organization_id uuid not null references public.organization(id),
  photographer_id uuid references auth.users(id),
  scheduled_at timestamptz not null,
  status text not null default 'planifiee' check (status in ('demandee', 'planifiee', 'faite', 'livree', 'annulee')),
  payment_id uuid,                                  -- clé étrangère ajoutée avec la facturation
  verification_case_id uuid references public.verification_case(id),
  tour_id uuid references public.tour(id),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index photo_mission_agenda_idx on public.photo_mission (photographer_id, scheduled_at);
create trigger photo_mission_touch before update on public.photo_mission for each row execute function app.touch_updated_at();

-- Validation finale : publie l'annonce et pose le badge.
create or replace function public.approve_listing_verification(p_case uuid, p_method text) returns void
language plpgsql security definer set search_path = public as $$
declare c public.verification_case; l public.listing;
begin
  if not app.is_staff(array['verificateur', 'photographe']) then
    raise exception 'Réservé à l''équipe de vérification' using errcode = '42501';
  end if;
  select * into c from public.verification_case where id = p_case for update;
  if c.subject_type <> 'listing' then raise exception 'Ce dossier ne concerne pas une annonce'; end if;
  select * into l from public.listing where id = c.listing_id for update;
  update public.verification_case set status = 'valide', closed_at = now(), method_code = p_method where id = p_case;
  update public.listing
     set verified_method_code = p_method, verified_at = now(),
         verified_facts_hash = app.listing_facts_hash(l),
         last_confirmed_at = now(),
         status_code = 'disponible',
         published_at = coalesce(published_at, now())
   where id = l.id;
  insert into public.listing_event (listing_id, event_type, actor_id, payload)
  values (l.id, 'verified', auth.uid(), jsonb_build_object('method', p_method, 'case_id', p_case));
end $$;
