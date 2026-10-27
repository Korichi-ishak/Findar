'use server';
import { redirect } from 'next/navigation';
import { revalidatePath } from 'next/cache';
import { toDzd } from '@/lib/format';
import { createClient } from '@/lib/supabase/server';

const num = (v: FormDataEntryValue | null) => (v === null || String(v).trim() === '' ? null : Number(String(v).replace(/\s/g, '').replace(',', '.')));

/** Crée bien + adresse + annonce, puis l'envoie en vérification si demandé. */
export async function createListing(formData: FormData) {
  const supabase = await createClient();
  const back = String(formData.get('back') ?? '/espace');
  let orgId = String(formData.get('org_id') ?? '');
  if (!orgId) {
    const { data, error } = await supabase.rpc('ensure_personal_organization');
    if (error) throw new Error(error.message);
    orgId = data as string;
  }

  const unit = String(formData.get('price_unit') ?? '') as 'DA' | 'centimes' | 'millions' | 'milliards';
  const amount = num(formData.get('price'));
  if (amount != null && !['DA', 'centimes', 'millions', 'milliards'].includes(unit)) throw new Error('Unité du prix obligatoire');

  const { data: commune } = await supabase.from('commune').select('id').eq('slug', String(formData.get('commune'))).single();
  const { data: claims } = await supabase.auth.getClaims();
  const uid = claims?.claims?.sub as string;

  const { data: prop, error: e1 } = await supabase.from('property')
    .insert({ commune_id: commune?.id, quartier: String(formData.get('quartier') ?? '') || null }).select('id').single();
  if (e1) throw new Error(e1.message);
  const { error: e2 } = await supabase.from('property_location').insert({
    property_id: prop.id, address_line: String(formData.get('address')), building: String(formData.get('building') ?? '') || null,
    lat: num(formData.get('lat')), lng: num(formData.get('lng')),
  });
  if (e2) throw new Error(e2.message);

  const { data: listing, error: e3 } = await supabase.from('listing').insert({
    property_id: prop.id, organization_id: orgId, created_by: uid,
    category_code: String(formData.get('category')), property_type_code: String(formData.get('type')),
    price_dzd: amount == null ? null : toDzd(amount, unit),
    rooms: num(formData.get('rooms')), surface_m2: num(formData.get('surface')), floor: num(formData.get('floor')),
    title: { fr: String(formData.get('title') ?? '') }, description: { fr: String(formData.get('description') ?? '') },
  }).select('id').single();
  if (e3) throw new Error(e3.message);

  if (formData.get('submit') === '1') {
    const { error } = await supabase.rpc('submit_listing', { p_listing: listing.id, p_method: String(formData.get('method') ?? 'visio') });
    if (error) throw new Error(error.message);
  }
  revalidatePath(back);
  redirect(`${back}/annonces/${listing.id}`);
}

export async function submitListing(formData: FormData) {
  const id = String(formData.get('listing_id'));
  const supabase = await createClient();
  const { error } = await supabase.rpc('submit_listing', { p_listing: id, p_method: String(formData.get('method') ?? 'visio') });
  if (error) throw new Error(error.message);
  revalidatePath(String(formData.get('back') ?? '/espace'));
}

export async function confirmStillAvailable(formData: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('confirm_listing_still_available', { p_listing: String(formData.get('listing_id')) });
  if (error) throw new Error(error.message);
  revalidatePath(String(formData.get('back') ?? '/espace'));
}
