-- =====================================================================
-- Findar · 002 · Identités : profils, organisations, membres, équipe Findar
-- Un particulier est une organisation de type « particulier » avec un seul
-- membre : une annonce appartient toujours à une organisation. Ouvrir les
-- particuliers plus largement, ou ajouter un type d'organisation, ne
-- change donc pas le modèle.
-- =====================================================================

create table public.profile (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  email extensions.citext,
  phone text,                                    -- format E.164, jamais affiché aux autres utilisateurs
  locale text not null default 'fr' check (locale in ('fr', 'ar', 'en')),
  otp_channel text not null default 'sms' check (otp_channel in ('sms', 'email')),
  notification_prefs jsonb not null default '{"push": true, "email": true, "sms": true}',
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create unique index profile_email_uq on public.profile (email) where deleted_at is null and email is not null;
create unique index profile_phone_uq on public.profile (phone) where deleted_at is null and phone is not null;
create trigger profile_touch before update on public.profile for each row execute function app.touch_updated_at();

create table public.organization (
  id uuid primary key default gen_random_uuid(),
  kind_code text not null references public.ref_org_kind(code),
  name text not null,
  slug text unique check (slug ~ '^[a-z0-9-]+$'),
  commune_id uuid references public.commune(id),
  description jsonb not null default '{}',
  verification_status text not null default 'non_verifiee'
    check (verification_status in ('non_verifiee', 'en_verification', 'verifiee', 'suspendue')),
  verified_at timestamptz,
  plan_code text references public.plan(code),
  response_minutes_avg int,                      -- cache, recalculé par tâche planifiée
  attributes jsonb not null default '{}',
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index organization_kind_idx on public.organization (kind_code) where deleted_at is null;
create trigger organization_touch before update on public.organization for each row execute function app.touch_updated_at();

create table public.organization_member (
  organization_id uuid not null references public.organization(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role_code text not null references public.ref_member_role(code),
  invited_by uuid references auth.users(id),
  joined_at timestamptz not null default now(),
  removed_at timestamptz,
  primary key (organization_id, user_id)
);
create index organization_member_user_idx on public.organization_member (user_id) where removed_at is null;

-- Équipe Findar : une personne peut cumuler plusieurs rôles.
create table public.staff_role_assignment (
  user_id uuid not null references auth.users(id) on delete cascade,
  role_code text not null references public.ref_staff_role(code),
  granted_by uuid references auth.users(id),
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  primary key (user_id, role_code)
);

-- ---------- fonctions d'autorisation (utilisées par les règles RLS) ----------
create or replace function app.uid() returns uuid
language sql stable as $$ select auth.uid() $$;

create or replace function app.is_staff(roles text[] default null) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.staff_role_assignment s
    where s.user_id = auth.uid() and s.revoked_at is null
      and (roles is null or s.role_code = any(roles) or s.role_code = 'super_admin')
  )
$$;

create or replace function app.is_org_member(org uuid, roles text[] default null) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.organization_member m
    where m.organization_id = org and m.user_id = auth.uid() and m.removed_at is null
      and (roles is null or m.role_code = any(roles))
  )
$$;

-- Création automatique du profil à l'inscription (Supabase Auth).
create or replace function app.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profile (id, email, phone, full_name)
  values (new.id, new.email, new.phone, coalesce(new.raw_user_meta_data->>'full_name', null))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function app.handle_new_user();

-- Un particulier qui publie pour la première fois reçoit son organisation individuelle.
create or replace function public.ensure_personal_organization() returns uuid
language plpgsql security definer set search_path = public as $$
declare
  org uuid;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  select m.organization_id into org
  from public.organization_member m join public.organization o on o.id = m.organization_id
  where m.user_id = auth.uid() and m.removed_at is null and o.kind_code = 'particulier' and o.deleted_at is null
  limit 1;
  if org is null then
    insert into public.organization (kind_code, name)
    values ('particulier', coalesce((select full_name from public.profile where id = auth.uid()), 'Particulier'))
    returning id into org;
    insert into public.organization_member (organization_id, user_id, role_code)
    values (org, auth.uid(), 'directeur');
  end if;
  return org;
end $$;
