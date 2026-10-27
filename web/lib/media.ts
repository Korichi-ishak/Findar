import { supabaseUrl } from '@/lib/env';

// Photos publiques : bucket « listings » (CDN plus tard : changer cette fonction seulement).
export const photoUrl = (path: string | null | undefined) =>
  path ? `${supabaseUrl}/storage/v1/object/public/listings/${path}` : null;
