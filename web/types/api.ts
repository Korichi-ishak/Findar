// Contrat entre le front et la base : la vue listing_public et les RPC.
// On ajoute des champs ici quand la vue en gagne ; on n'en retire jamais sans version.

export type Label = { fr: string; ar?: string; en?: string };
export type Locale = 'fr' | 'ar' | 'en';

export interface AdvertiserCard {
  kind: 'particulier' | 'agence' | 'promoteur' | string;
  name: string | null;
  slug?: string | null;
  verified: boolean;
  response_minutes_avg?: number | null;
}

export interface ListingPublic {
  id: string;
  ref_code: string;
  category_code: string;
  property_type_code: string;
  status_code: string;
  price_dzd: number | null;
  price_is_from: boolean;
  rent_advance_months: number | null;
  rooms: number | null;
  surface_m2: number | null;
  land_m2: number | null;
  floor: number | null;
  floors_total: number | null;
  year_built: number | null;
  price_m2_dzd: number | null;
  title: Partial<Label>;
  description: Partial<Label>;
  attributes: Record<string, unknown>;
  commune_slug: string;
  commune_label: Label;
  wilaya_code: string;
  quartier: string | null;
  lat: number | null;
  lng: number | null;
  verified_method_code: string | null;
  verified_at: string | null;
  last_confirmed_at: string | null;
  has_tour: boolean;
  cover_path: string | null;
  photo_count: number;
  advertiser: AdvertiserCard;
  organization_id: string;
  program_id: string | null;
  is_sponsored: boolean;
  published_at: string | null;
  updated_at: string;
}

/** Clés de search_listings(filters). Toutes facultatives ; la base ignore celles qu'elle ne connaît pas. */
export interface SearchFilters {
  category?: string;
  types?: string[];
  communes?: string[];
  price_min?: number;
  price_max?: number;
  rooms?: number[];
  rooms_min?: number;
  surface_min?: number;
  surface_max?: number;
  verified_only?: boolean;
  has_tour?: boolean;
  attributes?: Record<string, unknown>;
  poi?: Record<string, number>;
  bbox?: { s: number; w: number; n: number; e: number };
  q?: string;
}

export type SearchSort = 'recent' | 'price_asc' | 'price_desc' | 'surface_desc' | 'price_m2_asc';

export interface RefRow {
  code: string;
  label: Label;
  sort: number;
  active: boolean;
  meta: Record<string, unknown>;
}
