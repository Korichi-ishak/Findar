-- =====================================================================
-- Preuve que les décisions encore floues se changent SANS migration :
-- un UPDATE / INSERT dans un réglage ou un référentiel suffit.
-- (Rejoue après 10_workflow_rls.sql, mêmes utilisateurs.)
-- =====================================================================
\set QUIET on

-- 1. Le client passe la limite des particuliers de 2 à 3 annonces.
update public.app_setting set value = '3' where key = 'quota.particulier.active_listings';
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
select tests.ok(public.submit_listing(id) is not null, 'limite portée à 3 : la 3e annonce passe')
from public.listing where property_type_code = 'studio';

-- 2. Nouvel équipement filtrable : une ligne, et la recherche le connaît.
reset role;
insert into public.ref_attribute (code, label, value_type, group_code, filterable)
values ('cave', '{"fr":"Cave","ar":"قبو"}', 'bool', 'detail', true);
update public.listing set attributes = attributes || '{"cave": true}' where ref_code = 'F1000';
set role anon;
select set_config('request.jwt.claim.sub', '', false);
select tests.ok((select count(*) from public.search_listings('{"attributes":{"cave":true}}')) = 1, 'nouveau filtre « cave » sans migration');

-- 3. Nouveau statut public (ex. « sous offre ») : visible tout de suite.
reset role;
insert into public.ref_listing_status (code, label, sort, meta)
values ('sous_offre', '{"fr":"Sous offre"}', 65, '{"public": true, "contact": false, "counts_quota": true}');
update public.listing set status_code = 'sous_offre' where ref_code = 'F1000';
set role anon;
select tests.ok((select count(*) from public.listing_public where status_code = 'sous_offre') = 1, 'nouveau statut public reconnu partout');

-- 4. Le client décide qu'une seule confirmation suffit pour la visite.
reset role;
update public.ref_dossier_step set meta = meta || '{"policy":"one"}' where code = 'visite_confirmee';
update public.listing set status_code = 'disponible' where ref_code = 'F1000';
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000d', false);
select public.open_dossier(id) as d2 from public.listing where ref_code = 'F1000' \gset
select (public.propose_visit(:'d2', now() + interval '2 days')).id as v2 \gset
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
select tests.ok((public.confirm_visit(:'v2', 1)).status = 'confirmee', 'règle « une confirmation » appliquée sans migration');

-- 5. Adresse donnée 48 h avant au lieu de 24 h.
reset role;
update public.app_setting set value = '48' where key = 'visit.address_release_hours_before';
update public.ref_dossier_step set meta = meta || '{"policy":"both"}' where code = 'visite_confirmee';
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000d', false);
select (public.propose_visit(:'d2', now() + interval '5 days')).id as v3 \gset
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
select tests.ok((select address_released_at = starts_at - interval '48 hours' from public.confirm_visit(:'v3', 1)),
  'délai d''adresse passé à 48 h par un réglage');

reset role;
\echo 'Changements sans migration : OK.'
