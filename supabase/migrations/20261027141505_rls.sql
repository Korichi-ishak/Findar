-- =====================================================================
-- Findar · 007 · Règles d'accès (Row Level Security)
-- Principe : tout est fermé par défaut, chaque table ouvre explicitement
-- ce qu'elle montre. Le serveur (service_role) contourne ces règles pour
-- les tâches planifiées et les webhooks.
-- =====================================================================

create or replace function app.is_public_status(code text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select (meta->>'public')::boolean from public.ref_listing_status where ref_listing_status.code = is_public_status.code), false)
$$;

create or replace function app.listing_is_public(p_listing uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.listing l where l.id = p_listing and l.deleted_at is null and app.is_public_status(l.status_code))
$$;

create or replace function app.can_manage_listing(p_listing uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.listing l where l.id = p_listing and app.is_org_member(l.organization_id, array['directeur', 'agent']))
$$;

do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- ---------- référentiels : lecture pour tous, écriture super-admin ----------
do $$
declare t text;
begin
  foreach t in array array['ref_category', 'ref_property_type', 'ref_listing_status', 'ref_org_kind', 'ref_member_role',
    'ref_staff_role', 'ref_document_type', 'ref_verification_method', 'ref_verification_outcome', 'ref_dossier_step',
    'ref_poi_kind', 'ref_report_reason', 'ref_questionnaire_answer', 'ref_attribute', 'wilaya', 'commune', 'plan'] loop
    execute format('create policy read_all on public.%I for select using (true)', t);
    execute format('create policy admin_write on public.%I for all using (app.is_staff(array[''super_admin''])) with check (app.is_staff(array[''super_admin'']))', t);
  end loop;
end $$;

create policy read_public on public.app_setting for select using (is_public or app.is_staff());
create policy admin_write on public.app_setting for all using (app.is_staff(array['super_admin'])) with check (app.is_staff(array['super_admin']));

-- ---------- identités ----------
create policy self_read on public.profile for select using (id = auth.uid() or app.is_staff());
create policy self_update on public.profile for update using (id = auth.uid()) with check (id = auth.uid());
-- Les membres d'une même organisation voient leurs noms (boîte commune, équipe).
create policy coworker_read on public.profile for select using (exists (
  select 1 from public.organization_member a join public.organization_member b on b.organization_id = a.organization_id
  where a.user_id = auth.uid() and b.user_id = profile.id and a.removed_at is null and b.removed_at is null));

create policy read_public on public.organization for select
  using (deleted_at is null and (verification_status = 'verifiee' or app.is_org_member(id) or app.is_staff()));
-- Création d'une organisation pro : uniquement via public.create_pro_organization() (crée aussi le directeur).
create policy director_update on public.organization for update
  using (app.is_org_member(id, array['directeur']) or app.is_staff(array['commercial', 'verificateur']))
  with check (app.is_org_member(id, array['directeur']) or app.is_staff(array['commercial', 'verificateur']));

-- Statut de vérification, formule et dates : posés par l'équipe Findar seulement.
create or replace function app.guard_organization() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not app.is_staff() and (
       new.verification_status is distinct from old.verification_status
    or new.verified_at is distinct from old.verified_at
    or new.plan_code is distinct from old.plan_code
    or new.kind_code is distinct from old.kind_code) then
    raise exception 'Réservé à l''équipe Findar' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger organization_guard before update on public.organization
  for each row execute function app.guard_organization();

create policy member_read on public.organization_member for select
  using (user_id = auth.uid() or app.is_org_member(organization_id) or app.is_staff());
create policy director_manage on public.organization_member for all
  using (app.is_org_member(organization_id, array['directeur']) or app.is_staff(array['commercial']))
  with check (app.is_org_member(organization_id, array['directeur']) or app.is_staff(array['commercial']));

create policy staff_read on public.staff_role_assignment for select using (user_id = auth.uid() or app.is_staff());
create policy admin_manage on public.staff_role_assignment for all using (app.is_staff(array['super_admin'])) with check (app.is_staff(array['super_admin']));

-- ---------- biens et annonces ----------
create policy read_property on public.property for select using (true);   -- pas d'adresse exacte ici
create policy property_insert on public.property for insert with check (auth.uid() is not null);
create policy property_update on public.property for update
  using (app.is_staff() or exists (select 1 from public.listing l where l.property_id = property.id and app.can_manage_listing(l.id))
         or created_by = auth.uid())
  with check (auth.uid() is not null);

create or replace function app.can_edit_property(p uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select app.is_staff()
      or exists (select 1 from public.property x where x.id = p and x.created_by = auth.uid())
      or exists (select 1 from public.listing l where l.property_id = p and app.can_manage_listing(l.id))
$$;
create policy address_read on public.property_location for select using (app.can_see_address(property_id) or app.can_edit_property(property_id));
create policy address_write on public.property_location for all
  using (app.can_edit_property(property_id)) with check (app.can_edit_property(property_id));

create policy listing_read on public.listing for select
  using ((deleted_at is null and app.is_public_status(status_code)) or app.is_org_member(organization_id) or app.is_staff());
create policy listing_insert on public.listing for insert
  with check (app.is_org_member(organization_id, array['directeur', 'agent']) and status_code in ('brouillon', 'en_verification'));
create policy listing_update on public.listing for update
  using (app.is_org_member(organization_id, array['directeur', 'agent']) or app.is_staff())
  with check (app.is_org_member(organization_id, array['directeur', 'agent']) or app.is_staff());

-- Un annonceur ne publie pas lui-même : seuls les statuts « techniques » lui sont permis.
create or replace function app.guard_listing_status() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status_code is distinct from old.status_code and not app.is_staff()
     and auth.uid() is not null
     and new.status_code not in ('brouillon', 'en_verification', 'retiree') then
    raise exception 'Changement de statut réservé à un agent Findar' using errcode = '42501';
  end if;
  if not app.is_staff() and auth.uid() is not null and (
       new.verified_at is distinct from old.verified_at and new.verified_at is not null
       or new.verified_method_code is distinct from old.verified_method_code and new.verified_method_code is not null) then
    raise exception 'Le badge de vérification est posé par un agent Findar' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger listing_guard_status before update on public.listing
  for each row execute function app.guard_listing_status();

create policy media_read on public.listing_media for select using (app.listing_is_public(listing_id) or app.can_manage_listing(listing_id) or app.is_staff());
create policy media_write on public.listing_media for all using (app.can_manage_listing(listing_id) or app.is_staff()) with check (app.can_manage_listing(listing_id) or app.is_staff());

create policy event_read on public.listing_event for select
  using (app.is_staff() or app.can_manage_listing(listing_id)
         or (app.listing_is_public(listing_id) and event_type in ('created', 'price_changed', 'verified')));

create policy poi_read on public.listing_poi for select using (true);

create policy own_rows on public.favorite for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy own_rows on public.saved_search for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy own_rows on public.waitlist for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy staff_read on public.waitlist for select using (app.is_staff() or app.can_manage_listing(listing_id));

-- ---------- programmes neufs ----------
create policy program_read on public.program for select
  using ((deleted_at is null and app.is_public_status(status_code)) or app.is_org_member(organization_id) or app.is_staff());
create policy program_write on public.program for all
  using (app.is_org_member(organization_id, array['directeur', 'agent']) or app.is_staff())
  with check (app.is_org_member(organization_id, array['directeur', 'agent']) or app.is_staff());
do $$
declare t text;
begin
  foreach t in array array['program_typology', 'program_lot', 'program_update', 'program_payment_step'] loop
    execute format('create policy child_read on public.%I for select using (exists (select 1 from public.program p where p.id = program_id))', t);
    execute format('create policy child_write on public.%I for all using (exists (select 1 from public.program p where p.id = program_id and (app.is_org_member(p.organization_id, array[''directeur'', ''agent'']) or app.is_staff()))) with check (exists (select 1 from public.program p where p.id = program_id and (app.is_org_member(p.organization_id, array[''directeur'', ''agent'']) or app.is_staff())))', t);
  end loop;
end $$;

-- ---------- vérification ----------
create or replace function app.can_see_case(c public.verification_case) returns boolean
language sql stable security definer set search_path = public as $$
  select app.is_staff()
      or (c.listing_id is not null and app.can_manage_listing(c.listing_id))
      or (c.organization_id is not null and app.is_org_member(c.organization_id, array['directeur']))
      or (c.program_id is not null and exists (select 1 from public.program p where p.id = c.program_id and app.is_org_member(p.organization_id, array['directeur', 'agent'])))
$$;
create policy case_read on public.verification_case for select using (app.can_see_case(verification_case));
create policy case_submit on public.verification_case for insert with check (app.can_see_case(verification_case) and status = 'documents');
create policy case_staff on public.verification_case for update using (app.is_staff()) with check (app.is_staff());

create policy doc_read on public.verification_document for select
  using (exists (select 1 from public.verification_case c where c.id = case_id and app.can_see_case(c)));
create policy doc_upload on public.verification_document for insert
  with check (decision is null and exists (select 1 from public.verification_case c where c.id = case_id and app.can_see_case(c)));
create policy doc_decide on public.verification_document for update using (app.is_staff(array['verificateur'])) with check (app.is_staff(array['verificateur']));

create policy attempt_read on public.verification_attempt for select
  using (app.is_staff() or exists (select 1 from public.verification_case c where c.id = case_id and app.can_see_case(c)));
create policy attempt_staff on public.verification_attempt for all using (app.is_staff()) with check (app.is_staff());

create policy purge_staff on public.storage_purge_queue for select using (app.is_staff(array['super_admin']));

create policy tour_read on public.tour for select using (true);
create policy tour_staff on public.tour for all using (app.is_staff(array['photographe'])) with check (app.is_staff(array['photographe']));

create policy mission_read on public.photo_mission for select using (app.is_org_member(organization_id) or app.is_staff());
create policy mission_request on public.photo_mission for insert with check (app.is_org_member(organization_id, array['directeur', 'agent']) and status = 'demandee');
create policy mission_staff on public.photo_mission for update using (app.is_staff()) with check (app.is_staff());

-- ---------- dossiers ----------
create policy rule_read on public.availability_rule for select using (true);
create policy rule_write on public.availability_rule for all
  using (app.is_org_member(organization_id, array['directeur', 'agent', 'assistant'])) with check (app.is_org_member(organization_id, array['directeur', 'agent', 'assistant']));

create policy dossier_read on public.dossier for select using (app.dossier_side(id) is not null);
create policy dossier_open on public.dossier for insert
  with check (buyer_id = auth.uid() and app.listing_is_public(listing_id)
              and organization_id = (select l.organization_id from public.listing l where l.id = listing_id));
create policy dossier_update on public.dossier for update
  using (app.dossier_side(id) in ('seller', 'findar')) with check (app.dossier_side(id) in ('seller', 'findar'));

create policy event_read on public.dossier_event for select using (app.dossier_side(dossier_id) is not null);
create policy event_insert on public.dossier_event for insert with check (app.dossier_side(dossier_id) is not null);

create policy visit_read on public.visit for select using (app.dossier_side(dossier_id) is not null);
create policy visit_propose on public.visit for insert
  with check (app.dossier_side(dossier_id) in ('buyer', 'seller') and status = 'proposee'
              and buyer_confirmed_at is null and seller_confirmed_at is null);
-- Les confirmations passent par public.confirm_visit() ; pas d'UPDATE direct côté client.
create policy visit_staff on public.visit for update using (app.is_staff()) with check (app.is_staff());

create policy msg_read on public.message for select
  using (app.dossier_side(dossier_id) is not null and (moderation_status <> 'masque' or app.is_staff()));
create policy msg_send on public.message for insert with check (app.dossier_side(dossier_id) in ('buyer', 'seller', 'findar'));
create policy msg_moderate on public.message for update using (app.is_staff(array['moderateur'])) with check (app.is_staff(array['moderateur']));

create policy qa_read on public.questionnaire_answer for select using (app.dossier_side(dossier_id) is not null);
create policy qa_answer on public.questionnaire_answer for insert with check (app.dossier_side(dossier_id) = side);

create policy offer_read on public.offer for select using (app.dossier_side(dossier_id) is not null);
create policy offer_make on public.offer for insert with check (app.dossier_side(dossier_id) = made_by_side and status = 'proposee');
create policy offer_decide on public.offer for update
  using (app.dossier_side(dossier_id) in ('buyer', 'seller', 'findar')) with check (app.dossier_side(dossier_id) in ('buyer', 'seller', 'findar'));

create policy deal_read on public.deal for select using (app.dossier_side(dossier_id) is not null);
create policy deal_staff on public.deal for all using (app.is_staff()) with check (app.is_staff());

create policy call_staff on public.confirmation_call for all using (app.is_staff()) with check (app.is_staff());

-- ---------- facturation, notifications, modération ----------
create policy sub_read on public.subscription for select using (app.is_org_member(organization_id, array['directeur']) or app.is_staff());
create policy sub_staff on public.subscription for all using (app.is_staff(array['commercial', 'comptabilite'])) with check (app.is_staff(array['commercial', 'comptabilite']));

create policy pay_read on public.payment for select using (payer_id = auth.uid() or app.is_org_member(organization_id, array['directeur']) or app.is_staff(array['comptabilite']));
create policy pay_declare on public.payment for insert with check (payer_id = auth.uid() and status = 'en_attente');
create policy pay_staff on public.payment for update using (app.is_staff(array['comptabilite'])) with check (app.is_staff(array['comptabilite']));

create policy inv_read on public.invoice for select
  using (exists (select 1 from public.payment p where p.id = payment_id and (p.payer_id = auth.uid() or app.is_org_member(p.organization_id, array['directeur']) or app.is_staff(array['comptabilite']))));

create policy boost_read on public.boost for select using (true);
create policy boost_staff on public.boost for all using (app.is_staff()) with check (app.is_staff());

create policy notif_own on public.notification for select using (user_id = auth.uid());
create policy notif_mark_read on public.notification for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy delivery_staff on public.notification_delivery for select using (app.is_staff());

create policy report_create on public.report for insert with check (reporter_id = auth.uid());
create policy report_staff on public.report for all using (app.is_staff(array['moderateur'])) with check (app.is_staff(array['moderateur']));

create policy estimate_read on public.estimate_run for select using (true);
create policy audit_read on public.audit_log for select using (app.is_staff(array['super_admin']));
