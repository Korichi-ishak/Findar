export const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? '';
export const supabaseKey =
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? '';

/** Faux tant que .env.local n'est pas rempli : l'app s'affiche quand même, avec un bandeau. */
export const isSupabaseConfigured = Boolean(supabaseUrl && supabaseKey);
