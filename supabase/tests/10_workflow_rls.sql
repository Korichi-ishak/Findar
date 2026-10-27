-- =====================================================================
-- Tests de bout en bout : publication, vérification, visibilité,
-- dossier de visite, adresse, messagerie, quotas, journaux.
-- Chaque vérification lève une erreur si elle échoue (ON_ERROR_STOP).
-- =====================================================================
\set QUIET on
create schema tests;
grant usage on schema tests to anon, authenticated;

create function tests.ok(cond boolean, msg text) returns void language plpgsql as $$
begin
  if cond is not true then raise exception 'ÉCHEC : %', msg; end if;
  raise notice 'ok  %', msg;
end $$;

-- Exécute une requête et vérifie qu'elle échoue avec le code attendu.
create function tests.fails(q text, code text, msg text) returns void language plpgsql as $$
begin
  execute q;
  raise exception 'ÉCHEC (aucune erreur) : %', msg;
exception when others then
  if sqlstate <> code then raise exception 'ÉCHEC : % — attendu %, reçu % (%)', msg, code, sqlstate, sqlerrm; end if;
  raise notice 'ok  % (refusé %)', msg, code;
end $$;
grant execute on all functions in schema tests to anon, authenticated;

-- ---------- utilisateurs ----------
insert into auth.users (id, email, phone, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'proprio@test.dz', '+213550000001', '{"full_name":"Karim B."}'),
  ('00000000-0000-0000-0000-00000000000b', 'acheteur@test.dz', '+213550000002', '{"full_name":"Lina A."}'),
  ('00000000-0000-0000-0000-00000000000c', 'verif@findar.dz', null, '{"full_name":"Agent Findar"}'),
  ('00000000-0000-0000-0000-00000000000d', 'curieux@test.dz', null, '{}');
insert into public.staff_role_assignment (user_id, role_code) values ('00000000-0000-0000-0000-00000000000c', 'verificateur');
update public.app_setting set value = 'false' where key = 'commune.gate_enabled';

select tests.ok((select count(*) from pii.profile) = 4, 'profil créé automatiquement à l''inscription (schéma pii)');

-- ---------- le propriétaire crée son annonce ----------
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);

select public.ensure_personal_organization() as org \gset
select tests.ok(public.ensure_personal_organization() = :'org', 'organisation individuelle réutilisée (pas de doublon)');

insert into public.property (commune_id, quartier)
select id, 'Paradou' from public.commune where slug = 'hydra' returning id as prop \gset
insert into public.property_location (property_id, address_line, lat, lng)
values (:'prop', '12 rue des Pins, Hydra', 36.7440, 3.0360);

insert into public.listing (property_id, organization_id, created_by, category_code, property_type_code,
  price_dzd, rooms, surface_m2, floor, title, attributes)
values (:'prop', :'org', auth.uid(), 'vente', 'appartement', 32000000, 4, 120, 3,
  '{"fr":"F4 lumineux à Hydra"}', '{"ascenseur": true, "papiers": "acte"}')
returning id as listing \gset

select public.submit_listing(:'listing', 'visio') as vcase \gset
select tests.ok((select status_code from public.listing where id = :'listing') = 'en_verification', 'soumise : en vérification');
select tests.ok((select due_at > now() + interval '1 day' from public.verification_case where id = :'vcase'), 'échéance de vérification en jours ouvrés');

select tests.fails(format('update public.listing set status_code = %L where id = %L', 'disponible', :'listing'),
  '42501', 'l''annonceur ne peut pas se publier lui-même');
select tests.fails(format('update public.listing set verified_at = now() where id = %L', :'listing'),
  '42501', 'l''annonceur ne peut pas poser le badge');

insert into public.verification_document (case_id, document_type_code, storage_path, uploaded_by)
values (:'vcase', 'acte_propriete', 'verification/' || :'vcase' || '/acte.pdf', auth.uid()) returning id as doc \gset

-- ---------- un visiteur ne voit rien encore ----------
reset role; set role anon;
select set_config('request.jwt.claim.sub', '', false);
select tests.ok((select count(*) from public.listing_public) = 0, 'annonce non vérifiée invisible');
select tests.fails('select * from public.property_location', '42501', 'adresse exacte interdite à un visiteur');
select tests.fails('select * from pii.profile', '42501', 'schéma pii inaccessible directement');
select tests.ok((select count(*) from public.verification_document) = 0, 'pièces invisibles pour un visiteur');

-- ---------- l'agent Findar vérifie ----------
reset role; set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000c', false);
update public.verification_document set decision = 'conforme' where id = :'doc';
select tests.ok((select storage_path is null and purged_at is not null from public.verification_document where id = :'doc'),
  'pièce supprimée dès la décision, seul le résultat reste');
reset role;
select tests.ok((select count(*) = 1 from public.storage_purge_queue where path like '%acte.pdf'), 'fichier mis en file de suppression');
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
select tests.fails(format('select public.approve_listing_verification(%L, %L)', :'vcase', 'visio'), '42501',
  'un annonceur ne peut pas valider sa propre vérification');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000c', false);
select public.approve_listing_verification(:'vcase', 'visio');
select tests.ok((select status_code = 'disponible' and verified_at is not null from public.listing where id = :'listing'), 'validée : disponible + badge');

-- ---------- visibilité publique ----------
reset role; set role anon;
select set_config('request.jwt.claim.sub', '', false);
select tests.ok((select count(*) from public.listing_public) = 1, 'annonce vérifiée visible');
select tests.ok((select advertiser->>'name' is null and advertiser->>'kind' = 'particulier' from public.listing_public), 'un particulier n''est jamais nommé');
select tests.ok((select lat <> 36.7440 and abs(lat - 36.7440) < 0.002 from public.listing_public), 'position publique floutée (≤ 150 m)');
select tests.ok((select count(*) from public.search_listings('{"category":"vente","communes":["hydra"],"rooms_min":3,"attributes":{"ascenseur":true}}')) = 1, 'recherche filtrée : trouvée');
select tests.ok((select count(*) from public.search_listings('{"price_max": 10000000}')) = 0, 'recherche filtrée : prix max exclut');
select tests.ok((select count(*) from public.search_listings('{"q": "hydra"}')) = 1, 'recherche texte sans accents');
select tests.fails('select public.open_dossier(gen_random_uuid())', '42501', 'un visiteur doit se connecter pour contacter');
select tests.fails(format('select public.approve_listing_verification(%L, %L)', :'vcase', 'visio'), '42501', 'un visiteur ne peut appeler aucune fonction de gestion');

-- ---------- l'acheteur demande une visite ----------
reset role; set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
select public.open_dossier(:'listing') as dossier \gset
select tests.ok(public.open_dossier(:'listing') = :'dossier', 'un seul dossier ouvert par acheteur et annonce');
select (public.propose_visit(:'dossier', now() + interval '3 days')).id as visit \gset
select tests.ok((select status = 'proposee' and buyer_confirmed_at is not null from public.visit where id = :'visit'), 'visite proposée, côté acheteur confirmé');
select tests.ok((select count(*) from public.property_location) = 0, 'adresse cachée avant confirmation');

-- ---------- un inconnu ne voit pas le dossier ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000d', false);
select tests.ok((select count(*) from public.dossier) = 0, 'dossier invisible pour un tiers');
select tests.fails(format('insert into public.message (dossier_id, side, body) values (%L, %L, %L)', :'dossier', 'buyer', 'coucou'),
  '42501', 'un tiers ne peut pas écrire dans le dossier');
select tests.fails(format('select public.confirm_visit(%L, 1)', :'visit'), '42501', 'un tiers ne peut pas confirmer la visite');

-- ---------- le propriétaire confirme en un geste ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
select tests.fails(format('select public.confirm_visit(%L, 99)', :'visit'), '40001', 'confirmation avec une version périmée refusée');
select public.confirm_visit(:'visit', 1);
select tests.ok((select status = 'confirmee' and address_released_at = starts_at - interval '24 hours' from public.visit where id = :'visit'),
  'visite confirmée par les deux, adresse libérée la veille');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
select tests.ok((select count(*) from public.property_location) = 0, 'adresse encore cachée 3 jours avant');
reset role;
update public.visit set address_released_at = now() - interval '1 minute' where id = :'visit';
set role authenticated;
select tests.ok((select address_line from public.property_location) = '12 rue des Pins, Hydra', 'adresse visible la veille de la visite');

-- ---------- messagerie surveillée ----------
insert into public.message (dossier_id, side, body) values (:'dossier', 'seller', 'Bonjour, je serai là à l''heure.');
insert into public.message (dossier_id, side, body) values (:'dossier', 'buyer', 'Appelez-moi au 0555 12 34 56 sur WhatsApp');
select tests.ok((select side = 'buyer' from public.message order by created_at limit 1), 'le côté est déduit de la session, pas du client');
select tests.ok((select moderation_status = 'en_moderation' and flags @> '{phone,external_contact}' from public.message where body like 'Appelez%'),
  'numéro + WhatsApp détectés → modération');
select tests.ok((select moderation_status = 'ok' from public.message where body like 'Bonjour%'), 'message normal non signalé');

-- ---------- empreinte des faits : le badge tombe ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
update public.listing set price_dzd = 25000000 where id = :'listing';
select tests.ok((select (metadata->>'needs_reconfirmation')::boolean and verified_at is not null from public.listing where id = :'listing'),
  'baisse de prix > 20 % : reconfirmation demandée, badge gardé');
update public.listing set surface_m2 = 140 where id = :'listing';
select tests.ok((select verified_at is null and status_code = 'en_verification' from public.listing where id = :'listing'),
  'surface modifiée : badge retiré, retour en vérification');
reset role;
select tests.ok((select count(*) from public.listing_event where listing_id = :'listing' and event_type = 'facts_changed') = 1, 'changement journalisé');
select tests.fails('update public.listing_event set payload = ''{}''', 'P0001', 'journal de l''annonce en ajout seul');
select tests.fails('delete from public.dossier_event', 'P0001', 'journal du dossier en ajout seul');

-- ---------- quota : 2 annonces actives pour un particulier ----------
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
insert into public.property (commune_id) select id from public.commune where slug = 'kouba' returning id as prop2 \gset
insert into public.listing (property_id, organization_id, category_code, property_type_code, price_dzd, rooms, surface_m2)
values (:'prop2', :'org', 'location', 'appartement', 6000000, 3, 80) returning id as l2 \gset
select public.submit_listing(:'l2');
insert into public.listing (property_id, organization_id, category_code, property_type_code, price_dzd, rooms, surface_m2)
values (:'prop2', :'org', 'location', 'studio', 3000000, 1, 30) returning id as l3 \gset
select tests.fails(format('select public.submit_listing(%L)', :'l3'), 'P0003', 'troisième annonce active refusée (limite réglable)');

-- ---------- réservation confirmée par un agent ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000c', false);
select public.approve_listing_verification(:'vcase', 'visio');
insert into public.deal (dossier_id, listing_id, stage, agreed_price_dzd, confirmed_by)
values (:'dossier', :'listing', 'reservation', 24500000, auth.uid());
select tests.ok((select status_code = 'reservee' from public.listing where id = :'listing'), 'réservation : annonce réservée');
select tests.ok((select due_at::date = (now() + interval '15 days')::date from public.confirmation_call where reason = 'reservation'),
  'appel de contrôle planifié à 15 jours');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000d', false);
select tests.ok((select count(*) from public.deal) = 0, 'prix convenu invisible pour un tiers');
select tests.ok((select count(*) from public.listing_public where status_code = 'reservee') = 1, 'annonce réservée reste visible (liste d''attente)');

-- ---------- tâches planifiées ----------
reset role;
select tests.ok((select (app.run_scheduled_jobs()) ? 'calls_created'), 'tâches planifiées exécutées');
select tests.ok((select count(*) from public.audit_log where entity = 'deal') = 1, 'accord inscrit au journal d''audit');

-- ---------- données personnelles (schéma pii) ----------
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
select tests.ok((select count(*) from public.profile) = 1, 'un acheteur ne voit que son propre profil');
select tests.fails(format('update public.property_location set address_line = %L', 'piratée'), '42501', 'l''acheteur voit l''adresse mais ne peut pas la modifier')
  where exists (select 1 from public.property_location);
select tests.fails('update public.message set body = ''modifié''', '42501', 'un message envoyé ne se réécrit pas');
select tests.fails('delete from public.message', '42501', 'un message ne se supprime pas');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000d', false);
select tests.ok((select count(*) from public.message) = 0, 'un tiers ne lit pas les messages');
select tests.fails(format('insert into public.verification_attempt (case_id, method_code) values (%L, %L)', :'vcase', 'visio'), '42501',
  'un utilisateur ne peut pas inventer un contrôle de vérification');
reset role;

-- ---------- inscription d'une agence ----------
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000d', false);
select public.create_pro_organization('agence', 'Agence Test', 'kouba') as agency \gset
select tests.ok((select verification_status = 'en_verification' from public.organization where id = :'agency'), 'agence créée, en vérification');
select tests.ok(app.is_org_member(:'agency', array['directeur']), 'le créateur est directeur');
select tests.fails(format('update public.organization set verification_status = %L where id = %L', 'verifiee', :'agency'),
  '42501', 'une agence ne peut pas se déclarer vérifiée');
select tests.fails('insert into public.organization (kind_code, name) values (''agence'', ''Pirate'')', '42501', 'création d''organisation directe interdite');
reset role;

\echo 'Tous les tests sont passés.'
