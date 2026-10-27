import 'server-only';
import { createClient } from '@/lib/supabase/server';
import { isSupabaseConfigured } from '@/lib/env';
import type { ListingPublic, RefRow, SearchFilters, SearchSort } from '@/types/api';

export async function searchListings(filters: SearchFilters, sort: SearchSort = 'recent', page = 1, pageSize = 24) {
  if (!isSupabaseConfigured) return { rows: [] as ListingPublic[], error: null };
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('search_listings', { filters, sort, page_size: pageSize, page });
  return { rows: (data ?? []) as ListingPublic[], error };
}

export async function getListing(ref: string) {
  if (!isSupabaseConfigured) return null;
  const supabase = await createClient();
  const { data } = await supabase.from('listing_public').select('*').eq('ref_code', ref).maybeSingle();
  return data as ListingPublic | null;
}

/** Listes de valeurs (statuts, types, catégories…) : lues en base, jamais codées en dur. */
export async function getRefs(table: 'ref_category' | 'ref_property_type' | 'ref_listing_status' | 'ref_poi_kind') {
  if (!isSupabaseConfigured) return [] as RefRow[];
  const supabase = await createClient();
  const { data } = await supabase.from(table).select('*').eq('active', true).order('sort');
  return (data ?? []) as RefRow[];
}

export async function getCommunes() {
  if (!isSupabaseConfigured) return [] as { slug: string; label: { fr: string; ar?: string }; is_open: boolean }[];
  const supabase = await createClient();
  const { data } = await supabase.from('commune').select('slug, label, is_open').eq('wilaya_code', '16').order('slug');
  return data ?? [];
}

/** Lit les filtres depuis l'URL (?category=vente&communes=hydra,kouba&prix_max=…). */
export function filtersFromParams(p: Record<string, string | string[] | undefined>): { filters: SearchFilters; sort: SearchSort; page: number } {
  const s = (k: string) => (typeof p[k] === 'string' && p[k] !== '' ? (p[k] as string) : undefined);
  const n = (k: string) => (s(k) && !Number.isNaN(Number(s(k))) ? Number(s(k)) : undefined);
  const list = (k: string) => {
    const raw = p[k];
    const arr = Array.isArray(raw) ? raw : raw?.split(',');
    return arr?.filter(Boolean).length ? arr.filter(Boolean) : undefined;
  };
  const f: SearchFilters = {
    category: s('category'),
    types: list('types'),
    communes: list('communes'),
    price_min: n('prix_min'),
    price_max: n('prix_max'),
    rooms_min: n('pieces_min'),
    surface_min: n('surface_min'),
    verified_only: s('verifie') === '1' || undefined,
    has_tour: s('tour') === '1' || undefined,
    q: s('q'),
  };
  const poi = list('proche');   // ?proche=ecole,mosquee → distance par défaut de ref_poi_kind côté page
  if (poi?.length) f.poi = Object.fromEntries(poi.map((k) => [k, Number(s(`d_${k}`) ?? 800)]));
  Object.keys(f).forEach((k) => f[k as keyof SearchFilters] === undefined && delete f[k as keyof SearchFilters]);
  return { filters: f, sort: (s('tri') as SearchSort) ?? 'recent', page: n('page') ?? 1 };
}
