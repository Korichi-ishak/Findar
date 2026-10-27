import Link from 'next/link';
import { Empty, PageHead } from '@/components/Notice';
import { StatusBadge } from '@/components/StatusBadge';
import { dateFr } from '@/lib/format';
import { createClient } from '@/lib/supabase/server';
import { requireStaff } from '@/lib/staff';

export default async function Page() {
  await requireStaff(['verificateur', 'photographe']);
  const supabase = await createClient();
  const { data } = await supabase.from('verification_case')
    .select('id, subject_type, status, method_code, due_at, created_at, listing:listing_id(ref_code), organization:organization_id(name), program:program_id(name)')
    .is('closed_at', null).order('due_at', { ascending: true, nullsFirst: false });
  const now = Date.now();
  return (
    <>
      <PageHead title="File de vérification" />
      <p className="small muted">Les pièces sont effacées dès votre décision : seul le résultat reste. Un refus ou une correction demande toujours un motif.</p>
      {data?.length ? (
        <div className="scroll-x card"><table className="tbl">
          <thead><tr><th>Sujet</th><th>Étape</th><th>Méthode</th><th>Échéance</th><th /></tr></thead>
          <tbody>{data.map((c) => {
            const one = <T,>(x: T | T[] | null) => (Array.isArray(x) ? x[0] : x);
            const subject = c.subject_type === 'listing' ? `Annonce ${one(c.listing)?.ref_code ?? ''}` : c.subject_type === 'organization' ? one(c.organization)?.name : one(c.program)?.name;
            const late = c.due_at && new Date(c.due_at).getTime() < now;
            return (
              <tr key={c.id}>
                <td><strong>{subject}</strong></td>
                <td><StatusBadge code={c.status} /></td>
                <td>{c.method_code ?? '—'}</td>
                <td className="small">{late ? <span className="badge b-bad">En retard</span> : null} {dateFr(c.due_at)}</td>
                <td><Link className="btn btn-d btn-s" href={`/admin/verification/${c.id}`}>Traiter</Link></td>
              </tr>);
          })}</tbody></table></div>
      ) : <Empty>File vide.</Empty>}
    </>
  );
}
