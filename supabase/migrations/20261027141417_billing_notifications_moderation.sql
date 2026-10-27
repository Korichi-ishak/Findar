-- =====================================================================
-- Findar · 006 · Abonnements, paiements, notifications, modération,
-- estimation, journal d'audit
-- =====================================================================

create table public.subscription (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organization(id) on delete cascade,
  plan_code text not null references public.plan(code),
  starts_on date not null default current_date,
  ends_on date,
  status text not null default 'active' check (status in ('essai', 'active', 'en_retard', 'resiliee')),
  custom_quotas jsonb,                              -- formules sur devis : quotas propres
  created_at timestamptz not null default now()
);
create index subscription_org_idx on public.subscription (organization_id, starts_on desc);

create table public.payment (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organization(id),
  payer_id uuid references auth.users(id),
  purpose text not null check (purpose in ('abonnement', 'tour_360', 'mise_en_avant', 'autre')),
  reference_id uuid,                                -- abonnement, mission 360 ou mise en avant concernée
  amount_dzd bigint not null check (amount_dzd >= 0),
  method text not null check (method in ('cib', 'edahabia', 'virement', 'versement', 'gratuit')),
  provider text,                                    -- chargily, manuel
  provider_ref text,
  status text not null default 'en_attente' check (status in ('en_attente', 'paye', 'echoue', 'rembourse', 'refuse')),
  proof_path text,                                  -- justificatif de virement
  validated_by uuid references auth.users(id),
  paid_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index payment_provider_ref_uq on public.payment (provider, provider_ref) where provider_ref is not null;
alter table public.photo_mission add constraint photo_mission_payment_fk foreign key (payment_id) references public.payment(id);

create sequence public.invoice_seq;
create table public.invoice (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null unique references public.payment(id),
  number text not null unique default ('F-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('public.invoice_seq')::text, 5, '0')),
  issued_at timestamptz not null default now(),
  pdf_path text
);

create table public.boost (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listing(id) on delete cascade,
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null,
  payment_id uuid references public.payment(id),
  included_in_plan boolean not null default false,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

-- Notifications + file d'envoi (outbox) : un échec d'envoi se voit et se rejoue.
create table public.notification (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null,                               -- visit_confirmed, questionnaire, price_drop, saved_search_match…
  payload jsonb not null default '{}',              -- jamais le texte d'un message
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index notification_user_idx on public.notification (user_id, created_at desc);

create table public.notification_delivery (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.notification(id) on delete cascade,
  channel text not null check (channel in ('push', 'email', 'sms')),
  status text not null default 'en_attente' check (status in ('en_attente', 'envoye', 'livre', 'echec', 'abandonne')),
  attempts smallint not null default 0,
  last_error text,
  next_attempt_at timestamptz not null default now(),
  delivered_at timestamptz,
  created_at timestamptz not null default now()
);
create index notification_delivery_queue_idx on public.notification_delivery (next_attempt_at) where status in ('en_attente', 'echec');

-- Signalements et actions de modération
create table public.report (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid references auth.users(id),
  target_type text not null check (target_type in ('listing', 'message', 'organization', 'user', 'dossier')),
  target_id uuid not null,
  reason_code text not null references public.ref_report_reason(code),
  details text,
  status text not null default 'ouvert' check (status in ('ouvert', 'traite', 'rejete')),
  handled_by uuid references auth.users(id),
  handled_at timestamptz,
  action text,
  created_at timestamptz not null default now()
);
create index report_open_idx on public.report (created_at) where status = 'ouvert';

-- Estimations : chaque calcul est rejouable (version du modèle + comparables).
create table public.estimate_run (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid references public.listing(id) on delete cascade,
  params jsonb not null,                            -- commune, catégorie, pièces, surface…
  model_version text not null,
  comparable_listing_ids uuid[] not null default '{}',
  n_distinct int not null,
  low_dzd bigint,
  high_dzd bigint,
  confidence text check (confidence in ('faible', 'moyenne', 'elevee')),
  status text not null check (status in ('ok', 'donnees_insuffisantes')),
  created_at timestamptz not null default now(),
  check (status = 'donnees_insuffisantes' or (low_dzd is not null and high_dzd is not null and low_dzd <= high_dzd))
);
create index estimate_run_listing_idx on public.estimate_run (listing_id, created_at desc);

-- Journal d'audit générique (qui a changé quoi) sur les tables sensibles
create table public.audit_log (
  id bigint generated always as identity primary key,
  actor_id uuid,
  action text not null,
  entity text not null,
  entity_id text,
  before jsonb,
  after jsonb,
  created_at timestamptz not null default now()
);
create index audit_log_entity_idx on public.audit_log (entity, entity_id, created_at);
create trigger audit_log_append_only before update or delete on public.audit_log
  for each row execute function app.forbid_mutation();

create or replace function app.audit() returns trigger
language plpgsql security definer set search_path = public as $$
declare k text;
begin
  k := coalesce(tg_argv[0], 'id');
  insert into public.audit_log (actor_id, action, entity, entity_id, before, after)
  values (auth.uid(), tg_op, tg_table_name,
          coalesce(to_jsonb(new)->>k, to_jsonb(old)->>k),
          case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
          case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end);
  return coalesce(new, old);
end $$;

create trigger audit_app_setting after insert or update or delete on public.app_setting
  for each row execute function app.audit('key');
create trigger audit_staff_role after insert or update or delete on public.staff_role_assignment
  for each row execute function app.audit('user_id');
create trigger audit_organization after update on public.organization
  for each row execute function app.audit();
create trigger audit_verification_case after update on public.verification_case
  for each row execute function app.audit();
create trigger audit_deal after insert or update on public.deal
  for each row execute function app.audit();
create trigger audit_payment after update on public.payment
  for each row execute function app.audit();
