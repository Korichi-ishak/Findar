-- =====================================================================
-- Findar · 001 · Fondations
-- Règles (voir docs/DATABASE.md) :
--   * aucune valeur métier en ENUM Postgres : tables de référence ref_*
--     (on ajoute une valeur par INSERT, sans migration de type) ;
--   * libellés multilingues en jsonb {fr, ar, en} ;
--   * délais, seuils et règles de workflow dans app_setting (modifiables
--     sans redéployer) ;
--   * colonnes `attributes` / `metadata` jsonb comme soupape pour ce qui
--     n'est pas encore décidé.
-- =====================================================================

-- Extensions dans leur propre schéma (convention Supabase), toujours appelées qualifiées.
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists citext with schema extensions;
create extension if not exists unaccent with schema extensions;
create extension if not exists pg_trgm with schema extensions;
grant usage on schema extensions to public;

-- Schéma interne : fonctions utilitaires, jamais exposé par l'API.
create schema if not exists app;

-- ---------- utilitaires ----------
create or replace function app.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- Interdit UPDATE / DELETE sur les journaux (tables en ajout seul).
create or replace function app.forbid_mutation() returns trigger
language plpgsql as $$
begin
  raise exception 'Table % en ajout seul : % interdit', tg_table_name, tg_op
    using errcode = 'P0001';
end $$;

-- Un libellé multilingue doit au moins contenir le français.
create or replace function app.is_label(j jsonb) returns boolean
language sql immutable as $$
  select j is not null and jsonb_typeof(j) = 'object' and (j ? 'fr')
$$;

-- ---------- tables de référence (même forme pour toutes) ----------
-- code      : identifiant stable, jamais renommé (on désactive au lieu de supprimer)
-- label     : {fr, ar, en}
-- sort      : ordre d'affichage
-- active    : false = n'apparaît plus dans les formulaires, reste valide pour l'historique
-- meta      : paramètres propres au domaine (jsonb, évolutif)

create table public.ref_category (
  code text primary key check (code ~ '^[a-z0-9_]+$'),
  label jsonb not null check (app.is_label(label)),
  sort int not null default 0,
  active boolean not null default true,
  meta jsonb not null default '{}'
);
comment on table public.ref_category is 'Transaction / catégorie de recherche : vente, location, neuf, terrain, local…';

create table public.ref_property_type (like public.ref_category including all);
comment on table public.ref_property_type is 'Type de bien. meta.categories = catégories où il est proposé.';

create table public.ref_listing_status (like public.ref_category including all);
comment on table public.ref_listing_status is 'Statuts d''annonce. meta.public = visible dans la recherche ; meta.contact = contact ouvert.';

create table public.ref_org_kind (like public.ref_category including all);
create table public.ref_member_role (like public.ref_category including all);
comment on table public.ref_member_role is 'Rôles dans une agence / un promoteur. meta.permissions = liste de permissions.';
create table public.ref_staff_role (like public.ref_category including all);
create table public.ref_document_type (like public.ref_category including all);
comment on table public.ref_document_type is 'Pièces de vérification. meta.for = [particulier, agence, promoteur].';
create table public.ref_verification_method (like public.ref_category including all);
create table public.ref_verification_outcome (like public.ref_category including all);
create table public.ref_dossier_step (like public.ref_category including all);
comment on table public.ref_dossier_step is 'Étapes du dossier de visite. meta.policy = both | one | auto (qui confirme) ; meta.expires_hours.';
create table public.ref_poi_kind (like public.ref_category including all);
create table public.ref_report_reason (like public.ref_category including all);
create table public.ref_questionnaire_answer (like public.ref_category including all);
comment on table public.ref_questionnaire_answer is 'Réponses possibles au questionnaire après visite. meta.side = buyer | seller.';

-- Attributs libres d''une annonce (équipements, papiers, détails) :
-- ajouter un filtre = ajouter une ligne ici, sans toucher au schéma.
create table public.ref_attribute (
  code text primary key check (code ~ '^[a-z0-9_]+$'),
  label jsonb not null check (app.is_label(label)),
  value_type text not null check (value_type in ('bool', 'int', 'number', 'text', 'choice', 'choices')),
  options jsonb,                                  -- pour choice / choices : [{code, label}]
  categories text[] not null default '{}',        -- vide = toutes catégories
  group_code text not null default 'general',     -- immeuble, papiers, location, equipement…
  filterable boolean not null default false,
  sort int not null default 0,
  active boolean not null default true,
  meta jsonb not null default '{}'
);

-- ---------- géographie ----------
create table public.wilaya (
  code text primary key,                          -- '16' = Alger
  label jsonb not null check (app.is_label(label)),
  active boolean not null default true
);

create table public.commune (
  id uuid primary key default gen_random_uuid(),
  wilaya_code text not null references public.wilaya(code),
  slug text not null unique check (slug ~ '^[a-z0-9-]+$'),
  label jsonb not null check (app.is_label(label)),
  lat double precision,
  lng double precision,
  is_open boolean not null default false,         -- ouverte au public (seuil d''annonces vérifiées)
  opened_at timestamptz,
  meta jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index commune_wilaya_idx on public.commune (wilaya_code);

-- ---------- réglages modifiables sans redéploiement ----------
create table public.app_setting (
  key text primary key check (key ~ '^[a-z0-9_.]+$'),
  value jsonb not null,
  description text,
  is_public boolean not null default false,       -- lisible par le front sans connexion
  updated_at timestamptz not null default now(),
  updated_by uuid
);
create trigger app_setting_touch before update on public.app_setting
  for each row execute function app.touch_updated_at();

-- Lecture typée d''un réglage avec valeur par défaut.
create or replace function app.setting(k text, fallback jsonb default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce((select value from public.app_setting where key = k), fallback)
$$;
create or replace function app.setting_int(k text, fallback int) returns int
language sql stable as $$ select coalesce((app.setting(k))::text::int, fallback) $$;

-- ---------- formules d''abonnement ----------
create table public.plan (
  code text primary key check (code ~ '^[a-z0-9_]+$'),
  label jsonb not null check (app.is_label(label)),
  org_kinds text[] not null default '{agence}',
  price_dzd bigint check (price_dzd is null or price_dzd >= 0),   -- null = prix à venir / sur devis
  period text not null default 'mois' check (period in ('mois', 'an', 'unite', 'devis')),
  quotas jsonb not null default '{}',             -- {annonces: n, tournages_360_mois: n, mises_en_avant_mois: n, membres: n}
  sort int not null default 0,
  active boolean not null default true,
  meta jsonb not null default '{}'
);
