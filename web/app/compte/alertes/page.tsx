import Link from 'next/link';
import { Empty, PageHead } from '@/components/Notice';
import { createClient } from '@/lib/supabase/server';

export default async function Page() {
  const supabase = await createClient();
  const { data } = await supabase.from('saved_search').select('*').order('created_at', { ascending: false });
  return (
    <>
      <PageHead title="Recherches sauvegardées" />
      {data?.length ? (
        <div className="stack">{data.map((s) => (
          <div key={s.id} className="card pad row between">
            <div className="stack" style={{ gap: 2 }}><strong>{s.name ?? 'Recherche'}</strong><code className="tiny">{JSON.stringify(s.criteria)}</code></div>
            <Link className="btn btn-o btn-s" href={`/recherche?${new URLSearchParams(Object.entries(s.criteria as Record<string, string>)).toString()}`}>Voir</Link>
          </div>))}</div>
      ) : <Empty>Enregistrez une recherche pour être prévenu des nouvelles annonces vérifiées.</Empty>}
    </>
  );
}
