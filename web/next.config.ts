import type { NextConfig } from 'next';

const supabaseHost = process.env.NEXT_PUBLIC_SUPABASE_URL ? new URL(process.env.NEXT_PUBLIC_SUPABASE_URL).hostname : undefined;

const config: NextConfig = {
  experimental: { authInterrupts: true },   // forbidden() pour les espaces non autorisés
  images: {
    // Photos : Supabase Storage aujourd'hui, CDN demain (ajouter l'hôte ici).
    remotePatterns: supabaseHost ? [{ protocol: 'https', hostname: supabaseHost }] : [],
  },
};

export default config;
