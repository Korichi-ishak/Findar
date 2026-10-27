import { moderateMessage } from '@/app/actions/admin';
import { Empty, PageHead } from '@/components/Notice';
import { dateFr } from '@/lib/format';
import { createClient } from '@/lib/supabase/server';
import { requireStaff } from '@/lib/staff';

export default async function Page() {
  await requireStaff(['moderateur']);
  const supabase = await createClient();
  const [msgs, reports] = await Promise.all([
    supabase.from('message').select('*').eq('moderation_status', 'en_moderation').order('created_at').limit(100),
    supabase.from('report').select('*').eq('status', 'ouvert').order('created_at').limit(100),
  ]);
  return (
    <>
      <PageHead title="Modération" />
      <h2 className="h-s">Messages signalés automatiquement</h2>
      {msgs.data?.length ? <div className="stack">{msgs.data.map((m) => (
        <form key={m.id} action={moderateMessage} className="card pad stack">
          <input type="hidden" name="message_id" value={m.id} />
          <span className="small muted">{dateFr(m.created_at)} · {m.side} · motifs : {m.flags.join(', ')}</span>
          <p>{m.body}</p>
          <div className="row"><button className="btn btn-o btn-s" name="status" value="ok">Laisser passer</button><button className="btn btn-d btn-s" name="status" value="masque">Masquer</button></div>
        </form>))}</div> : <Empty>Aucun message en attente.</Empty>}
      <h2 className="h-s">Signalements</h2>
      {reports.data?.length ? <table className="tbl card"><tbody>{reports.data.map((r) => (
        <tr key={r.id}><td>{r.target_type}</td><td>{r.reason_code}</td><td className="small">{r.details}</td><td className="small">{dateFr(r.created_at)}</td></tr>))}</tbody></table>
        : <Empty>Aucun signalement ouvert.</Empty>}
    </>
  );
}
