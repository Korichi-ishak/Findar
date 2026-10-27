'use server';
import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';

// Toutes les étapes passent par des fonctions de la base (RPC) : le côté
// (acheteur / vendeur / Findar) est déduit de la session, jamais du formulaire.

export async function contactListing(formData: FormData) {
  const listingId = String(formData.get('listing_id'));
  const ref = String(formData.get('ref'));
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  if (!claims?.claims) redirect(`/connexion?next=/annonce/${ref}`);
  const { data, error } = await supabase.rpc('open_dossier', { p_listing: listingId });
  if (error) redirect(`/annonce/${ref}?erreur=${encodeURIComponent(error.message)}`);
  redirect(`/compte/dossiers/${data}`);
}

export async function proposeVisit(formData: FormData) {
  const dossier = String(formData.get('dossier_id'));
  const startsAt = new Date(String(formData.get('starts_at'))).toISOString();
  const supabase = await createClient();
  const { error } = await supabase.rpc('propose_visit', { p_dossier: dossier, p_starts_at: startsAt });
  back(dossier, error);
}

export async function confirmVisit(formData: FormData) {
  const dossier = String(formData.get('dossier_id'));
  const supabase = await createClient();
  const { error } = await supabase.rpc('confirm_visit', {
    p_visit: String(formData.get('visit_id')),
    p_version: Number(formData.get('version')),
  });
  back(dossier, error);
}

export async function sendMessage(formData: FormData) {
  const dossier = String(formData.get('dossier_id'));
  const body = String(formData.get('body') ?? '').trim();
  if (!body) return;
  const supabase = await createClient();
  // side est recalculé par la base ; la valeur envoyée ici est ignorée.
  const { error } = await supabase.from('message').insert({ dossier_id: dossier, side: 'buyer', body });
  back(dossier, error);
}

function back(dossier: string, error: { message: string } | null) {
  for (const p of ['/compte/dossiers', '/espace/demandes', '/pro/demandes']) revalidatePath(`${p}/${dossier}`);
  if (error) throw new Error(error.message);
}
