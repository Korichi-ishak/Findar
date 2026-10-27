import { setPaymentStatus } from '@/app/actions/admin';
import { Empty, PageHead } from '@/components/Notice';
import { dateFr, dzd } from '@/lib/format';
import { createClient } from '@/lib/supabase/server';
import { requireStaff } from '@/lib/staff';

export default async function Page() {
  await requireStaff(['comptabilite']);
  const supabase = await createClient();
  const { data } = await supabase.from('payment').select('*').eq('status', 'en_attente').order('created_at');
  return (
    <>
      <PageHead title="Paiements et virements" />
      <p className="small muted">CIB / EDAHABIA via Chargily : validés automatiquement par le webhook. Virements et versements : à valider ici avec le justificatif.</p>
      {data?.length ? <div className="scroll-x card"><table className="tbl">
        <thead><tr><th>Objet</th><th>Montant</th><th>Moyen</th><th>Reçu</th><th /></tr></thead>
        <tbody>{data.map((p) => (
          <tr key={p.id}><td>{p.purpose}</td><td className="num">{dzd(p.amount_dzd)}</td><td>{p.method}</td><td className="small">{dateFr(p.created_at)}</td>
            <td><form action={setPaymentStatus} className="row"><input type="hidden" name="payment_id" value={p.id} />
              <button className="btn btn-d btn-s" name="status" value="paye">Valider</button>
              <button className="btn btn-o btn-s" name="status" value="refuse">Refuser</button></form></td></tr>))}</tbody>
      </table></div> : <Empty>Aucun paiement en attente.</Empty>}
    </>
  );
}
