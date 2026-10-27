import { notFound } from 'next/navigation';
import { ListingCard } from '@/components/ListingCard';
import { createClient } from '@/lib/supabase/server';
import { isSupabaseConfigured } from '@/lib/env';
import { getLocale, tr } from '@/lib/i18n';
import type { ListingPublic } from '@/types/api';

export default async function Agency({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  if (!isSupabaseConfigured) notFound();
  const locale = await getLocale();
  const supabase = await createClient();
  const { data: org } = await supabase.from('organization').select('id, name, description').eq('slug', slug).maybeSingle();
  if (!org) notFound();
  const { data } = await supabase.from('listing_public').select('*').eq('organization_id', org.id).order('published_at', { ascending: false });
  return (
    <div className="wrap sec stack" style={{ gap: 20 }}>
      <h1 className="h-l">{org.name}</h1>
      {tr(org.description, locale) && <p className="muted">{tr(org.description, locale)}</p>}
      <div className="grid g4">{((data ?? []) as ListingPublic[]).map((l) => <ListingCard key={l.id} l={l} locale={locale} />)}</div>
    </div>
  );
}
