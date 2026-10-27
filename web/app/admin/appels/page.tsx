import { closeCall } from '@/app/actions/admin';
import { Empty, PageHead } from '@/components/Notice';
import { dateFr } from '@/lib/format';
import { createClient } from '@/lib/supabase/server';
import { requireStaff } from '@/lib/staff';

const REASON: Record<string, string> = {
  apres_visite: '48 h après la visite', reservation: '15 jours après la réservation', sans_reponse: 'Sans réponse',
  contradiction: 'Réponses contradictoires', inactivite: 'Annonce inactive', autre: 'Autre',
};

export default async function Page() {
  await requireStaff(['verificateur', 'commercial']);
  const supabase = await createClient();
  const { data } = await supabase.from('confirmation_call').select('*, listing:listing_id(ref_code)').is('done_at', null).order('due_at').limit(200);
  return (
    <>
      <PageHead title="Appels de confirmation" />
      <p className="small muted">Le statut d&apos;un bien ne change qu&apos;après votre appel, même si le questionnaire a été rempli.</p>
      {data?.length ? <div className="stack">{data.map((c) => {
        const l = Array.isArray(c.listing) ? c.listing[0] : c.listing;
        return (
          <form key={c.id} action={closeCall} className="card pad row between">
            <input type="hidden" name="call_id" value={c.id} />
            <span><strong>{l?.ref_code}</strong> · {REASON[c.reason]} · <span className="small muted">à faire le {dateFr(c.due_at)}</span></span>
            <span className="row">
              <input name="note" className="inp" placeholder="Note" style={{ width: 200 }} />
              <button className="btn btn-o btn-s" name="outcome" value="toujours_disponible">Toujours disponible</button>
              <button className="btn btn-o btn-s" name="outcome" value="accord_confirme">Accord confirmé</button>
              <button className="btn btn-o btn-s" name="outcome" value="vendu_ailleurs">Vendu ailleurs</button>
              <button className="btn btn-g btn-s" name="outcome" value="injoignable">Injoignable</button>
            </span>
          </form>);
      })}</div> : <Empty>Aucun appel à passer.</Empty>}
    </>
  );
}
