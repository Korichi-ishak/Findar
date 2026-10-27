-- =====================================================================
-- Findar · 008 · API publique et règles métier
-- Le front lit des vues et appelle des fonctions (RPC), jamais les tables
-- brutes pour la recherche : on peut renommer / découper une table en
-- gardant la même vue, sans casser l'application.
-- Tous les seuils viennent de app_setting (voir seed.sql).
-- =====================================================================

-- ---------- outils ----------
-- Jours ouvrés algériens : dimanche → jeudi (vendredi, samedi fermés).
create or replace function app.add_working_days(ts timestamptz, days int) returns timestamptz
language plpgsql stable as $$
declare d timestamptz := ts; n int := 0; off int[];
begin
  off := coalesce((select array(select jsonb_array_elements_text(app.setting('calendar.weekend_dow', '[5,6]'))::int)), array[5,6]);
  while n < days loop
    d := d + interval '1 day';
    if not (extract(dow from d at time zone 'Africa/Algiers')::int = any(off)) then n := n + 1; end if;
  end loop;
  return d;
end $$;

-- Position publique floutée : décalage stable (même bien = même point) dans un rayon réglable.
create or replace function app.blur_point(lat double precision, lng double precision, seed uuid, radius_m int,
  out blat double precision, out blng double precision)
language plpgsql immutable as $$
declare h bytea := decode(md5(seed::text), 'hex'); a double precision; r double precision;
begin
  if lat is null or lng is null then return; end if;
  a := (get_byte(h, 0) * 256 + get_byte(h, 1)) / 65535.0 * 2 * pi();
  r := radius_m * (0.35 + 0.65 * (get_byte(h, 2) / 255.0));
  blat := lat + (r * cos(a)) / 111320.0;
  blng := lng + (r * sin(a)) / (111320.0 * cos(radians(lat)));
end $$;

create or replace function app.sync_approx_position() returns trigger
language plpgsql security definer set search_path = public as $$
declare b record;
begin
  select * into b from app.blur_point(new.lat, new.lng, new.property_id, app.setting_int('map.blur_radius_m', 150));
  update public.property set approx_lat = b.blat, approx_lng = b.blng where id = new.property_id;
  return new;
end $$;
create trigger property_location_blur after insert or update of lat, lng on public.property_location
  for each row execute function app.sync_approx_position();

-- Carte d'identité publique de l'annonceur : un particulier n'est jamais nommé.
create or replace function app.org_public_card(org uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when o.kind_code = 'particulier'
    then jsonb_build_object('kind', o.kind_code, 'name', null, 'verified', true)
    else jsonb_build_object('kind', o.kind_code, 'name', o.name, 'slug', o.slug,
                            'verified', o.verification_status = 'verifiee',
                            'response_minutes_avg', o.response_minutes_avg) end
  from public.organization o where o.id = org
$$;

-- ---------- vue publique des annonces ----------
create or replace view public.listing_public with (security_invoker = on) as
select
  l.id, l.ref_code, l.category_code, l.property_type_code, l.status_code,
  l.price_dzd, l.price_is_from, l.rent_advance_months,
  l.rooms, l.surface_m2, l.land_m2, l.floor, l.floors_total, l.year_built,
  case when l.surface_m2 > 0 and l.price_dzd is not null then round(l.price_dzd / l.surface_m2) end as price_m2_dzd,
  l.title, l.description, l.attributes,
  c.slug as commune_slug, c.label as commune_label, c.wilaya_code,
  p.quartier, p.approx_lat as lat, p.approx_lng as lng,      -- jamais l'adresse exacte
  l.verified_method_code, l.verified_at, l.last_confirmed_at,
  exists (select 1 from public.tour t where t.listing_id = l.id and t.public_url is not null) as has_tour,
  (select m.storage_path from public.listing_media m where m.listing_id = l.id and m.kind = 'photo' order by m.sort limit 1) as cover_path,
  (select count(*) from public.listing_media m where m.listing_id = l.id and m.kind = 'photo')::int as photo_count,
  app.org_public_card(l.organization_id) as advertiser,
  l.organization_id, l.program_id,
  coalesce(l.sponsored_until > now(), false)
    or exists (select 1 from public.boost b where b.listing_id = l.id and now() between b.starts_at and b.ends_at) as is_sponsored,
  l.published_at, l.updated_at
from public.listing l
join public.property p on p.id = l.property_id
join public.commune c on c.id = p.commune_id
where l.deleted_at is null
  and app.is_public_status(l.status_code)
  and (c.is_open or not (app.setting('commune.gate_enabled', 'true'::jsonb))::text::boolean);

comment on view public.listing_public is 'Annonces visibles. Contrat stable pour le front : ajouter des colonnes, ne jamais en retirer sans version.';

-- ---------- recherche ----------
-- filters (toutes les clés facultatives, on en ajoute sans casser les appels existants) :
-- {category, types[], communes[], price_min, price_max, rooms[], rooms_min, surface_min, surface_max,
--  verified_only, has_tour, attributes{code: valeur}, poi{kind: distance_max_m}, bbox{s,w,n,e}, q}
create or replace function public.search_listings(filters jsonb default '{}', sort text default 'recent',
  page_size int default 24, page int default 1)
returns setof public.listing_public
language plpgsql stable as $$
declare f jsonb := coalesce(filters, '{}');
begin
  return query
  select v.* from public.listing_public v
  where (f->>'category' is null or v.category_code = f->>'category')
    and (f->'types' is null or v.property_type_code in (select jsonb_array_elements_text(f->'types')))
    and (f->'communes' is null or v.commune_slug in (select jsonb_array_elements_text(f->'communes')))
    and (f->>'price_min' is null or v.price_dzd >= (f->>'price_min')::bigint)
    and (f->>'price_max' is null or v.price_dzd <= (f->>'price_max')::bigint)
    and (f->'rooms' is null or v.rooms in (select jsonb_array_elements_text(f->'rooms')::smallint))
    and (f->>'rooms_min' is null or v.rooms >= (f->>'rooms_min')::smallint)
    and (f->>'surface_min' is null or v.surface_m2 >= (f->>'surface_min')::numeric)
    and (f->>'surface_max' is null or v.surface_m2 <= (f->>'surface_max')::numeric)
    and (coalesce((f->>'verified_only')::boolean, false) = false or v.verified_at is not null)
    and (coalesce((f->>'has_tour')::boolean, false) = false or v.has_tour)
    and (f->'attributes' is null or v.attributes @> (f->'attributes'))
    and (f->'bbox' is null or (v.lat between (f->'bbox'->>'s')::float and (f->'bbox'->>'n')::float
                               and v.lng between (f->'bbox'->>'w')::float and (f->'bbox'->>'e')::float))
    and (f->'poi' is null or not exists (
          select 1 from jsonb_each_text(f->'poi') want
          where not exists (select 1 from public.listing_poi lp
                            where lp.listing_id = v.id and lp.poi_kind_code = want.key and lp.distance_m <= want.value::int)))
    and (f->>'q' is null or extensions.unaccent('extensions.unaccent', coalesce(v.title->>'fr', '') || ' ' || coalesce(v.quartier, '') || ' ' || v.ref_code)
                            ilike '%' || extensions.unaccent('extensions.unaccent', f->>'q') || '%')
  order by
    v.is_sponsored desc,
    case when sort = 'price_asc' then v.price_dzd end asc nulls last,
    case when sort = 'price_desc' then v.price_dzd end desc nulls last,
    case when sort = 'surface_desc' then v.surface_m2 end desc nulls last,
    case when sort = 'price_m2_asc' then v.price_m2_dzd end asc nulls last,
    v.published_at desc nulls last
  limit least(greatest(page_size, 1), 100) offset (greatest(page, 1) - 1) * least(greatest(page_size, 1), 100);
end $$;

-- ---------- quota des particuliers ----------
create or replace function app.check_listing_quota() returns trigger
language plpgsql security definer set search_path = public as $$
declare kind text; n int; max_n int;
begin
  if not coalesce((select (meta->>'counts_quota')::boolean from public.ref_listing_status where code = new.status_code), false) then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.status_code = new.status_code then return new; end if;
  select kind_code into kind from public.organization where id = new.organization_id;
  max_n := app.setting_int('quota.' || kind || '.active_listings', -1);   -- -1 = pas de limite (agences : le plan décide)
  if max_n < 0 then return new; end if;
  select count(*) into n from public.listing l
  join public.ref_listing_status s on s.code = l.status_code
  where l.organization_id = new.organization_id and l.id <> new.id and l.deleted_at is null
    and coalesce((s.meta->>'counts_quota')::boolean, false);
  if n >= max_n then
    raise exception 'Limite de % annonce(s) active(s) atteinte', max_n using errcode = 'P0003';
  end if;
  return new;
end $$;
create trigger listing_quota before insert or update of status_code on public.listing
  for each row execute function app.check_listing_quota();

-- ---------- inscription pro : organisation + directeur + dossier de vérification ----------
create or replace function public.create_pro_organization(p_kind text, p_name text, p_commune text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare org uuid;
begin
  if auth.uid() is null then raise exception 'Connexion requise' using errcode = '42501'; end if;
  if p_kind not in ('agence', 'promoteur') then raise exception 'Type d''organisation inconnu' using errcode = '23514'; end if;
  insert into public.organization (kind_code, name, commune_id, verification_status)
  values (p_kind, p_name, (select id from public.commune where slug = p_commune), 'en_verification')
  returning id into org;
  insert into public.organization_member (organization_id, user_id, role_code) values (org, auth.uid(), 'directeur');
  insert into public.verification_case (subject_type, organization_id, method_code, submitted_by, due_at)
  values ('organization', org, 'documents', auth.uid(),
          app.add_working_days(now(), app.setting_int('verification.sla_working_days', 2)));
  return org;
end $$;

-- ---------- annonceur : soumettre à vérification ----------
create or replace function public.submit_listing(p_listing uuid, p_method text default 'visio') returns uuid
language plpgsql security definer set search_path = public as $$
declare l public.listing; case_id uuid;
begin
  select * into l from public.listing where id = p_listing for update;
  if l.id is null or not app.is_org_member(l.organization_id, array['directeur', 'agent']) then
    raise exception 'Accès refusé' using errcode = '42501';
  end if;
  if l.status_code not in ('brouillon', 'a_corriger') then return null; end if;
  update public.listing set status_code = 'en_verification' where id = p_listing;
  select id into case_id from public.verification_case
   where listing_id = p_listing and closed_at is null order by created_at desc limit 1;
  if case_id is null then
    insert into public.verification_case (subject_type, listing_id, method_code, submitted_by, due_at)
    values ('listing', p_listing, p_method, auth.uid(),
            app.add_working_days(now(), app.setting_int('verification.sla_working_days', 2)))
    returning id into case_id;
  else
    update public.verification_case set status = 'documents', method_code = p_method,
      due_at = app.add_working_days(now(), app.setting_int('verification.sla_working_days', 2))
    where id = case_id;
  end if;
  return case_id;
end $$;

-- Refus / demande de correction : toujours avec un motif.
create or replace function public.request_listing_changes(p_case uuid, p_reason text, p_final boolean default false) returns void
language plpgsql security definer set search_path = public as $$
declare c public.verification_case;
begin
  if not app.is_staff(array['verificateur', 'photographe']) then raise exception 'Accès refusé' using errcode = '42501'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'Un motif est obligatoire' using errcode = '23514'; end if;
  select * into c from public.verification_case where id = p_case for update;
  update public.verification_case set status = case when p_final then 'refuse' else 'a_corriger' end,
    decision_reason = p_reason, closed_at = case when p_final then now() end
  where id = p_case;
  if c.listing_id is not null then
    update public.listing set status_code = 'a_corriger' where id = c.listing_id;
  end if;
end $$;

-- ---------- acheteur : ouvrir un dossier, proposer une visite ----------
create or replace function public.open_dossier(p_listing uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare d uuid; org uuid;
begin
  if auth.uid() is null then raise exception 'Connexion requise' using errcode = '42501'; end if;
  select l.organization_id into org from public.listing l
   join public.ref_listing_status s on s.code = l.status_code
   where l.id = p_listing and l.deleted_at is null and coalesce((s.meta->>'contact')::boolean, false);
  if org is null then raise exception 'Cette annonce n''accepte pas de contact' using errcode = 'P0004'; end if;
  if app.is_org_member(org) then raise exception 'C''est votre annonce' using errcode = 'P0004'; end if;
  select id into d from public.dossier where listing_id = p_listing and buyer_id = auth.uid() and closed_at is null;
  if d is null then
    insert into public.dossier (listing_id, buyer_id, organization_id) values (p_listing, auth.uid(), org) returning id into d;
    insert into public.dossier_event (dossier_id, step_code, kind, side) values (d, 'contact', 'proposed', 'buyer');
  end if;
  return d;
end $$;

create or replace function public.propose_visit(p_dossier uuid, p_starts_at timestamptz, p_minutes int default 30) returns public.visit
language plpgsql security definer set search_path = public as $$
declare s text; v public.visit; hrs int;
begin
  s := app.dossier_side(p_dossier);
  if s is null or s not in ('buyer', 'seller') then raise exception 'Accès refusé' using errcode = '42501'; end if;
  if p_starts_at <= now() then raise exception 'Créneau passé' using errcode = '23514'; end if;
  select coalesce((meta->>'expires_hours')::int, 24) into hrs from public.ref_dossier_step where code = 'visite_demandee';
  insert into public.visit (dossier_id, starts_at, ends_at, proposed_by_side, expires_at,
                            buyer_confirmed_at, seller_confirmed_at)
  values (p_dossier, p_starts_at, p_starts_at + make_interval(mins => p_minutes), s,
          least(now() + make_interval(hours => hrs), p_starts_at),
          case when s = 'buyer' then now() end, case when s = 'seller' then now() end)
  returning * into v;
  insert into public.dossier_event (dossier_id, step_code, kind, side, payload)
  values (p_dossier, 'visite_demandee', 'proposed', s, jsonb_build_object('visit_id', v.id, 'starts_at', p_starts_at));
  return v;
end $$;

-- ---------- messagerie : détection numéro / argent / contact externe ----------
-- Les motifs sont dans app_setting.moderation.message_patterns : on les ajuste sans migration.
create or replace function app.message_defaults() returns trigger
language plpgsql security definer set search_path = public as $$
declare s text; k text; pat text;
begin
  if auth.uid() is not null then
    s := app.dossier_side(new.dossier_id);
    if s is null then raise exception 'Accès refusé' using errcode = '42501'; end if;
    new.sender_id := auth.uid();
    new.side := s;
  end if;
  for k, pat in select key, value from jsonb_each_text(app.setting('moderation.message_patterns', '{}')) loop
    if new.body ~* pat and not (k = any(new.flags)) then new.flags := new.flags || k; end if;
  end loop;
  if cardinality(new.flags) > 0 then new.moderation_status := 'en_moderation'; end if;
  update public.dossier set last_activity_at = now() where id = new.dossier_id;
  return new;
end $$;

-- ---------- accords : appel de contrôle planifié ----------
create or replace function app.deal_schedule_call() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.stage = 'reservation' then
    insert into public.confirmation_call (reason, dossier_id, listing_id, due_at)
    values ('reservation', new.dossier_id, new.listing_id,
            now() + make_interval(days => app.setting_int('status.call_after_reservation_days', 15)));
    update public.listing set status_code = 'reservee' where id = new.listing_id;
  elsif new.stage = 'compromis' then
    update public.listing set status_code = 'compromis_signe' where id = new.listing_id;
  elsif new.stage in ('vente', 'location') then
    update public.listing set status_code = 'vendue_findar' where id = new.listing_id;
  end if;
  return new;
end $$;
create trigger deal_after_insert after insert on public.deal for each row execute function app.deal_schedule_call();

-- ---------- tâches planifiées (appelées par pg_cron ou une fonction serveur) ----------
create or replace function app.run_scheduled_jobs() returns jsonb
language plpgsql security definer set search_path = public as $$
declare n_exp int; n_calls int; n_ask int; n_hide int; n_open int;
begin
  -- 1. propositions de visite expirées
  with x as (update public.visit set status = 'expiree', version = version + 1
             where status = 'proposee' and expires_at < now() returning id)
  select count(*) into n_exp from x;

  -- 2. appel Findar 48 h après chaque visite confirmée (une fois)
  with x as (
    insert into public.confirmation_call (reason, dossier_id, listing_id, due_at)
    select 'apres_visite', v.dossier_id, d.listing_id,
           v.starts_at + make_interval(hours => app.setting_int('status.call_after_visit_hours', 48))
    from public.visit v join public.dossier d on d.id = v.dossier_id
    where v.status = 'confirmee' and v.starts_at < now()
      and not exists (select 1 from public.confirmation_call c where c.dossier_id = v.dossier_id and c.reason = 'apres_visite'
                      and c.created_at > v.starts_at)
    returning 1)
  select count(*) into n_calls from x;

  -- 3. 30 jours sans activité : on demande à l'annonceur
  with x as (
    update public.listing l set metadata = l.metadata || jsonb_build_object('inactivity_asked_at', now())
    where app.is_public_status(l.status_code) and l.deleted_at is null
      and coalesce(l.last_activity_at, l.published_at, l.created_at) < now() - make_interval(days => app.setting_int('listing.inactivity_days', 30))
      and l.metadata->>'inactivity_asked_at' is null
    returning l.id)
  select count(*) into n_ask from x;

  -- 4. sans réponse après 7 jours : annonce masquée (statut réglable)
  with x as (
    update public.listing l set status_code = coalesce(app.setting('listing.inactivity_hide_status') #>> '{}', 'suspendue'),
                                metadata = (l.metadata - 'inactivity_asked_at') || jsonb_build_object('hidden_reason', 'inactivite')
    where app.is_public_status(l.status_code)
      and (l.metadata->>'inactivity_asked_at')::timestamptz < now() - make_interval(days => app.setting_int('listing.inactivity_grace_days', 7))
    returning l.id)
  select count(*) into n_hide from x;

  -- 5. ouverture des communes au seuil d'annonces vérifiées
  with x as (
    update public.commune c set is_open = true, opened_at = now()
    where not c.is_open and (
      select count(*) from public.listing l join public.property p on p.id = l.property_id
      where p.commune_id = c.id and l.verified_at is not null and app.is_public_status(l.status_code)
    ) >= app.setting_int('commune.open_threshold', 30)
    returning c.id)
  select count(*) into n_open from x;

  return jsonb_build_object('visits_expired', n_exp, 'calls_created', n_calls,
                            'inactivity_asked', n_ask, 'hidden', n_hide, 'communes_opened', n_open);
end $$;

-- L'annonceur répond « toujours disponible » : on efface la question.
create or replace function public.confirm_listing_still_available(p_listing uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not app.can_manage_listing(p_listing) then raise exception 'Accès refusé' using errcode = '42501'; end if;
  update public.listing set metadata = metadata - 'inactivity_asked_at', last_activity_at = now() where id = p_listing;
  insert into public.listing_event (listing_id, event_type, actor_id) values (p_listing, 'owner_confirmed_available', auth.uid());
end $$;

-- ---------- indicateurs de marché (jamais moins de k annonces) ----------
create or replace function public.market_price_m2(p_commune text, p_category text default 'vente', p_months int default 12)
returns table (month date, median_price_m2 numeric, n int)
language sql stable security definer set search_path = public as $$
  with src as (
    select date_trunc('month', coalesce(l.published_at, l.created_at))::date as m,
           l.price_dzd / l.surface_m2 as pm2
    from public.listing l join public.property p on p.id = l.property_id join public.commune c on c.id = p.commune_id
    where c.slug = p_commune and l.category_code = p_category and l.surface_m2 > 0 and l.price_dzd > 0
      and l.verified_at is not null and l.deleted_at is null
      and coalesce(l.published_at, l.created_at) >= date_trunc('month', now()) - make_interval(months => p_months - 1)
  )
  select m, round(percentile_cont(0.5) within group (order by pm2)::numeric), count(*)::int
  from src group by m
  having count(*) >= app.setting_int('insights.min_sample', 5)
  order by m
$$;

-- ---------- droits d'exécution ----------
revoke all on function app.run_scheduled_jobs() from public;
grant usage on schema app to anon, authenticated;
grant select on public.listing_public to anon, authenticated;
