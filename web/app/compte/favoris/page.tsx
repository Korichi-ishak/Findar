import { ListingCard } from '@/components/ListingCard';
import { Empty, PageHead } from '@/components/Notice';
import { getLocale } from '@/lib/i18n';
import { createClient } from '@/lib/supabase/server';
import type { ListingPublic } from '@/types/api';

export default async function Page() {
  const supabase = await createClient();
  const locale = await getLocale();
  const { data: favs } = await supabase.from('favorite').select('listing_id').order('created_at', { ascending: false });
  const ids = (favs ?? []).map((f) => f.listing_id);
  const { data } = ids.length ? await supabase.from('listing_public').select('*').in('id', ids) : { data: [] };
  return (
    <>
      <PageHead title="Favoris" />
      {data?.length ? <div className="grid g3">{(data as ListingPublic[]).map((l) => <ListingCard key={l.id} l={l} locale={locale} />)}</div>
        : <Empty>Aucun favori. Les annonces vendues ou retirées disparaissent d&apos;ici.</Empty>}
    </>
  );
}
