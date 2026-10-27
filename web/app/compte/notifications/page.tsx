import { Empty, PageHead } from '@/components/Notice';
import { dateFr } from '@/lib/format';
import { createClient } from '@/lib/supabase/server';

export default async function Page() {
  const supabase = await createClient();
  const { data } = await supabase.from('notification').select('*').order('created_at', { ascending: false }).limit(50);
  return (
    <>
      <PageHead title="Notifications" />
      {data?.length ? (
        <div className="card">{data.map((n) => (
          <div key={n.id} className="pad row between" style={{ borderBottom: '1px solid var(--line-2)', fontWeight: n.read_at ? 400 : 700 }}>
            <span>{n.kind}</span><span className="small muted">{dateFr(n.created_at)}</span>
          </div>))}</div>
      ) : <Empty>Rien de nouveau.</Empty>}
    </>
  );
}
