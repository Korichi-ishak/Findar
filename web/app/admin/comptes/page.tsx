import { setOrgStatus } from '@/app/actions/admin';
import { PageHead } from '@/components/Notice';
import { StatusBadge } from '@/components/StatusBadge';
import { dateFr } from '@/lib/format';
import { createClient } from '@/lib/supabase/server';
import { requireStaff } from '@/lib/staff';

export default async function Page() {
  await requireStaff(['commercial', 'verificateur']);
  const supabase = await createClient();
  const { data } = await supabase.from('organization').select('id, name, kind_code, verification_status, plan_code, created_at')
    .in('kind_code', ['agence', 'promoteur']).is('deleted_at', null).order('created_at', { ascending: false });
  return (
    <>
      <PageHead title="Comptes et agences" />
      <p className="small muted">Agence : RC + agrément vérifiés une fois. Promoteur : RC + permis de construire.</p>
      <div className="scroll-x card"><table className="tbl">
        <thead><tr><th>Nom</th><th>Type</th><th>Statut</th><th>Formule</th><th>Créé</th><th /></tr></thead>
        <tbody>{(data ?? []).map((o) => (
          <tr key={o.id}><td><strong>{o.name}</strong></td><td>{o.kind_code}</td><td><StatusBadge code={o.verification_status === 'verifiee' ? 'valide' : o.verification_status} label={o.verification_status} /></td>
            <td>{o.plan_code ?? '—'}</td><td className="small">{dateFr(o.created_at)}</td>
            <td><form action={setOrgStatus} className="row"><input type="hidden" name="org_id" value={o.id} />
              <button className="btn btn-d btn-s" name="status" value="verifiee">Vérifiée</button>
              <button className="btn btn-o btn-s" name="status" value="suspendue">Suspendre</button></form></td></tr>))}</tbody>
      </table></div>
    </>
  );
}
