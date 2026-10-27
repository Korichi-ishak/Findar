-- =====================================================================
-- Findar · 009 · Isolation des données personnelles (schéma pii)
--
-- Décision : Supabase traite (API, règles, calculs) ; les données
-- personnelles seront STOCKÉES sur un serveur en Algérie dès qu'il existe.
--
-- Ce qui est personnel est regroupé dans le schéma `pii`, jamais exposé par
-- l'API. Le front y accède par des vues du schéma public qui portent
-- elles-mêmes les règles d'accès (WHERE + WITH CHECK OPTION + triggers de
-- garde), et non par la RLS : la RLS ne s'applique pas aux tables
-- distantes. Le jour du transfert, chaque table pii devient une table
-- distante (postgres_fdw vers le serveur algérien) portant le même nom :
-- les vues, les fonctions et l'application ne changent pas.
-- Voir docs/DATA_RESIDENCY.md.
-- =====================================================================

create schema if not exists pii;
revoke all on schema pii from public;

-- ---------- déplacement des tables ----------
alter table public.profile set schema pii;
alter table public.property_location set schema pii;
alter table public.message set schema pii;
alter table public.verification_attempt set schema pii;
-- Contenu de verification_attempt : compte rendu, captures du bien.

-- Les fonctions écrivent directement dans pii (elles ne passent pas par les vues).
create or replace function app.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into pii.profile (id, email, phone, full_name)
  values (new.id, new.email, new.phone, coalesce(new.raw_user_meta_data->>'full_name', null))
  on conflict (id) do nothing;
  return new;
end $$;

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
    values ('particulier', coalesce((select full_name from pii.profile where id = auth.uid()), 'Particulier'))
    returning id into org;
    insert into public.organization_member (organization_id, user_id, role_code)
    values (org, auth.uid(), 'directeur');
  end if;
  return org;
end $$;

-- ---------- règles d'accès (les mêmes qu'avant, portées par les vues) ----------
create or replace function app.is_coworker(p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.organization_member a join public.organization_member b on b.organization_id = a.organization_id
    where a.user_id = auth.uid() and b.user_id = p_user and a.removed_at is null and b.removed_at is null)
$$;

create or replace function app.case_visible(p_case uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.verification_case c where c.id = p_case and app.can_see_case(c))
$$;

-- Écritures : ce que la vue ne peut pas exprimer seule.
create or replace function app.pii_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return coalesce(new, old); end if;   -- serveur / tâches planifiées
  case tg_table_name
    when 'profile' then
      if tg_op <> 'UPDATE' or (new.id <> auth.uid() and not app.is_staff(array['super_admin'])) then
        raise exception 'Profil : modification réservée à son titulaire' using errcode = '42501';
      end if;
    when 'property_location' then
      if not app.can_edit_property(coalesce(new.property_id, old.property_id)) then
        raise exception 'Adresse : modification réservée à l''annonceur' using errcode = '42501';
      end if;
    when 'message' then
      if tg_op = 'DELETE' then raise exception 'Un message ne se supprime pas' using errcode = '42501'; end if;
      if tg_op = 'UPDATE' and not app.is_staff(array['moderateur']) and (
           new.body is distinct from old.body or new.side is distinct from old.side
        or new.sender_id is distinct from old.sender_id or new.flags is distinct from old.flags
        or new.moderation_status is distinct from old.moderation_status) then
        raise exception 'Seule la lecture d''un message peut être marquée' using errcode = '42501';
      end if;
    when 'verification_attempt' then
      if not app.is_staff() then raise exception 'Réservé à l''équipe Findar' using errcode = '42501'; end if;
  end case;
  return coalesce(new, old);
end $$;

create trigger pii_guard before insert or update or delete on pii.profile for each row execute function app.pii_guard();
create trigger pii_guard before insert or update or delete on pii.property_location for each row execute function app.pii_guard();
create trigger pii_guard before update or delete on pii.message for each row execute function app.pii_guard();
create trigger pii_guard before insert or update or delete on pii.verification_attempt for each row execute function app.pii_guard();

-- ---------- vues publiques (même nom qu'avant : le front ne change pas) ----------
-- security_barrier : le filtre s'applique avant toute fonction fournie par l'appelant.
create view public.profile with (security_barrier) as
  select * from pii.profile
  where deleted_at is null and (id = auth.uid() or app.is_coworker(id) or app.is_staff())
  with cascaded check option;

create view public.property_location with (security_barrier) as
  select * from pii.property_location
  where app.can_see_address(property_id) or app.can_edit_property(property_id)
  with cascaded check option;

create view public.message with (security_barrier) as
  select * from pii.message
  where app.dossier_side(dossier_id) is not null and (moderation_status <> 'masque' or app.is_staff())
  with cascaded check option;

create view public.verification_attempt with (security_barrier) as
  select * from pii.verification_attempt
  where app.is_staff() or app.case_visible(case_id)
  with cascaded check option;

comment on view public.profile is 'Accès aux profils (pii). Règles dans la vue + trigger pii_guard ; marche aussi quand pii.profile sera distante.';
comment on view public.property_location is 'Adresse exacte (pii) : annonceur, équipe, acheteur la veille d''une visite confirmée.';
comment on view public.message is 'Messagerie (pii). Le côté et la modération sont calculés par la base.';
comment on view public.verification_attempt is 'Contrôles du bien (pii) : comptes rendus, captures.';

-- Droits : lecture partout où la vue le permet ; écriture seulement là où c'est prévu.
revoke all on public.profile, public.property_location, public.message, public.verification_attempt from anon, authenticated;
grant select, update on public.profile to authenticated;
grant select, insert, update, delete on public.property_location to authenticated;
grant select, insert, update on public.message to authenticated;
grant select, insert, update on public.verification_attempt to authenticated;
