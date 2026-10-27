-- =====================================================================
-- Findar · 003 · Biens, annonces, médias, historique, programmes neufs
-- property = le bien physique (une adresse) ; listing = une annonce de ce
-- bien par une organisation. Deux agences qui publient le même bien
-- partagent la même property (dédoublonnage pour l'estimation).
-- L'adresse exacte vit dans property_location, protégée par RLS.
-- =====================================================================

create table public.property (
  id uuid primary key default gen_random_uuid(),
  commune_id uuid not null references public.commune(id),
  quartier text,
  approx_lat double precision,                    -- position publique, floutée (rayon en réglage)
  approx_lng double precision,
  dedup_key text,                                 -- calculé : commune + géohash + étage + surface
  created_by uuid default auth.uid() references auth.users(id),
  attributes jsonb not null default '{}',
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index property_commune_idx on public.property (commune_id);
create index property_dedup_idx on public.property (dedup_key);
create trigger property_touch before update on public.property for each row execute function app.touch_updated_at();

create table public.property_location (
  property_id uuid primary key references public.property(id) on delete cascade,
  address_line text not null,
  building text,
  access_notes text,
  lat double precision,
  lng double precision,
  updated_at timestamptz not null default now()
);
comment on table public.property_location is 'Adresse exacte. Visible par l''annonceur, l''équipe Findar, et un acheteur la veille d''une visite confirmée.';

create sequence public.listing_ref_seq start 1000;

create table public.listing (
  id uuid primary key default gen_random_uuid(),
  ref_code text not null unique default ('F' || nextval('public.listing_ref_seq')),
  property_id uuid not null references public.property(id),
  organization_id uuid not null references public.organization(id),
  created_by uuid references auth.users(id),
  assigned_to uuid references auth.users(id),     -- agent responsable (facultatif)
  category_code text not null references public.ref_category(code),
  property_type_code text not null references public.ref_property_type(code),
  status_code text not null default 'brouillon' references public.ref_listing_status(code),
  -- faits principaux (filtrés et triés : vraies colonnes)
  price_dzd bigint check (price_dzd is null or price_dzd > 0),
  price_is_from boolean not null default false,  -- « à partir de » (programmes neufs)
  rent_advance_months smallint check (rent_advance_months between 0 and 60),
  rooms smallint check (rooms between 0 and 50), -- F3 = 3
  surface_m2 numeric(10,2) check (surface_m2 > 0),
  land_m2 numeric(12,2) check (land_m2 > 0),
  floor smallint,
  floors_total smallint,
  year_built smallint,
  -- texte
  title jsonb not null default '{}',
  description jsonb not null default '{}',
  -- tout le reste : équipements, papiers, détails (défini dans ref_attribute)
  attributes jsonb not null default '{}',
  -- vérification (cache, la source est verification_case / verification_attempt)
  verified_method_code text references public.ref_verification_method(code),
  verified_at timestamptz,
  verified_facts_hash text,
  last_confirmed_at timestamptz,                  -- dernière confirmation de disponibilité par un agent
  -- cycle de vie
  published_at timestamptz,
  status_changed_at timestamptz not null default now(),
  last_activity_at timestamptz,                   -- dernier contact / message (règle « 30 jours sans activité »)
  sponsored_until timestamptz,
  program_id uuid,                                -- clé étrangère ajoutée plus bas
  view_count int not null default 0,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index listing_search_idx on public.listing (status_code, category_code, price_dzd) where deleted_at is null;
create index listing_org_idx on public.listing (organization_id) where deleted_at is null;
create index listing_property_idx on public.listing (property_id);
create index listing_attributes_idx on public.listing using gin (attributes jsonb_path_ops);
create trigger listing_touch before update on public.listing for each row execute function app.touch_updated_at();

create table public.listing_media (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listing(id) on delete cascade,
  kind text not null default 'photo' check (kind in ('photo', 'plan', 'video', 'cover_360')),
  storage_path text not null,
  room_label text,                                -- séjour, cuisine, chambre… (code libre, évolutif)
  width int, height int,
  sort int not null default 0,
  created_at timestamptz not null default now()
);
create index listing_media_listing_idx on public.listing_media (listing_id, sort);

-- Journal de l'annonce (ajout seul) : prix, statuts, vérifications, faits modifiés.
create table public.listing_event (
  id bigint generated always as identity primary key,
  listing_id uuid not null references public.listing(id) on delete cascade,
  event_type text not null,                       -- created, price_changed, status_changed, facts_changed, verified, confirmed_available, viewed_360…
  actor_id uuid,
  payload jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index listing_event_listing_idx on public.listing_event (listing_id, created_at);
create trigger listing_event_append_only before update or delete on public.listing_event
  for each row execute function app.forbid_mutation();

-- Lieux à proximité (calculés une fois, puis lus : pas d'appel Google Maps à l'affichage).
create table public.listing_poi (
  listing_id uuid not null references public.listing(id) on delete cascade,
  poi_kind_code text not null references public.ref_poi_kind(code),
  distance_m int not null check (distance_m >= 0),
  name text,
  computed_at timestamptz not null default now(),
  primary key (listing_id, poi_kind_code)
);

-- ---------- empreinte des faits vérifiés ----------
-- Si ces faits changent après vérification, le badge tombe (règle du conseil).
create or replace function app.listing_facts_hash(l public.listing) returns text
language sql immutable as $$
  select md5(concat_ws('|', l.property_id, l.category_code, l.property_type_code, l.rooms, l.surface_m2, l.land_m2, l.floor))
$$;

create or replace function app.listing_track_changes() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  pct numeric;
  limit_pct int := app.setting_int('listing.reverify_price_change_pct', 20);
begin
  if tg_op = 'INSERT' then
    insert into public.listing_event (listing_id, event_type, actor_id, payload)
    values (new.id, 'created', auth.uid(), jsonb_build_object('status', new.status_code, 'price_dzd', new.price_dzd));
    return new;
  end if;

  if new.status_code is distinct from old.status_code then
    new.status_changed_at := now();
    insert into public.listing_event (listing_id, event_type, actor_id, payload)
    values (new.id, 'status_changed', auth.uid(), jsonb_build_object('from', old.status_code, 'to', new.status_code));
  end if;

  if new.price_dzd is distinct from old.price_dzd then
    insert into public.listing_event (listing_id, event_type, actor_id, payload)
    values (new.id, 'price_changed', auth.uid(), jsonb_build_object('from', old.price_dzd, 'to', new.price_dzd));
    if old.price_dzd is not null and new.price_dzd is not null and old.verified_at is not null then
      pct := abs(new.price_dzd - old.price_dzd) * 100.0 / old.price_dzd;
      if pct > limit_pct then
        new.metadata := new.metadata || jsonb_build_object('needs_reconfirmation', true);
      end if;
    end if;
  end if;

  if old.verified_at is not null and app.listing_facts_hash(new) is distinct from old.verified_facts_hash
     and (app.setting('listing.reverify_on_material_change', 'true'::jsonb))::text::boolean then
    new.verified_at := null;
    new.verified_method_code := null;
    insert into public.listing_event (listing_id, event_type, actor_id, payload)
    values (new.id, 'facts_changed', auth.uid(), jsonb_build_object('badge_removed', true));
    if exists (select 1 from public.ref_listing_status s where s.code = new.status_code and (s.meta->>'public')::boolean) then
      new.status_code := 'en_verification';
      new.status_changed_at := now();
    end if;
  end if;
  return new;
end $$;

create trigger listing_track_ins after insert on public.listing for each row execute function app.listing_track_changes();
create trigger listing_track_upd before update on public.listing for each row execute function app.listing_track_changes();

-- ---------- côté acheteur ----------
create table public.favorite (
  user_id uuid not null references auth.users(id) on delete cascade,
  listing_id uuid not null references public.listing(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, listing_id)
);

create table public.saved_search (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text,
  criteria jsonb not null,                         -- mêmes clés que la recherche (évolutif)
  channels text[] not null default '{push,email}',
  active boolean not null default true,
  last_notified_at timestamptz,
  created_at timestamptz not null default now()
);
create index saved_search_user_idx on public.saved_search (user_id);

create table public.waitlist (
  listing_id uuid not null references public.listing(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  notified_at timestamptz,
  primary key (listing_id, user_id)
);

-- ---------- programmes neufs ----------
create table public.program (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organization(id),
  name text not null,
  slug text unique check (slug ~ '^[a-z0-9-]+$'),
  commune_id uuid not null references public.commune(id),
  formula_code text,                              -- VSP, LPP, promotionnel… (texte libre normalisé)
  delivery_label text,                            -- « T4 2027 »
  progress_pct smallint check (progress_pct between 0 and 100),
  description jsonb not null default '{}',
  status_code text not null default 'brouillon' references public.ref_listing_status(code),
  permit_verified_at timestamptz,
  attributes jsonb not null default '{}',
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create trigger program_touch before update on public.program for each row execute function app.touch_updated_at();
alter table public.listing add constraint listing_program_fk foreign key (program_id) references public.program(id);

create table public.program_typology (
  id uuid primary key default gen_random_uuid(),
  program_id uuid not null references public.program(id) on delete cascade,
  rooms smallint not null,
  surface_m2 numeric(10,2),
  price_from_dzd bigint,
  showcase_listing_id uuid references public.listing(id),   -- appartement témoin (360°)
  sort int not null default 0
);

create table public.program_lot (
  id uuid primary key default gen_random_uuid(),
  program_id uuid not null references public.program(id) on delete cascade,
  typology_id uuid references public.program_typology(id),
  block text not null,
  floor smallint not null,
  number text not null,
  status text not null default 'disponible' check (status in ('disponible', 'reserve', 'vendu', 'bloque')),
  updated_at timestamptz not null default now(),
  unique (program_id, block, floor, number)
);
create trigger program_lot_touch before update on public.program_lot for each row execute function app.touch_updated_at();

create table public.program_update (
  id uuid primary key default gen_random_uuid(),
  program_id uuid not null references public.program(id) on delete cascade,
  title text not null,
  happened_on date not null default current_date,
  media jsonb not null default '[]',
  created_at timestamptz not null default now()
);

create table public.program_payment_step (
  id uuid primary key default gen_random_uuid(),
  program_id uuid not null references public.program(id) on delete cascade,
  label jsonb not null check (app.is_label(label)),
  pct numeric(5,2) not null check (pct > 0 and pct <= 100),
  sort int not null default 0
);
