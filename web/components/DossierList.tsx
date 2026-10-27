import Link from 'next/link';
import { StatusBadge } from '@/components/StatusBadge';
import { dateFr } from '@/lib/format';
import { createClient } from '@/lib/supabase/server';
import { Empty } from '@/components/Notice';

/** Liste de dossiers filtrée par acheteur ou par organisation (boîte commune). */
export async function DossierList({ base, buyerId, orgId }: { base: string; buyerId?: string; orgId?: string }) {
  const supabase = await createClient();
  let q = supabase.from('dossier').select('id, current_step_code, last_activity_at, closed_at, listing:listing_id (ref_code, title)')
    .order('last_activity_at', { ascending: false }).limit(100);
  if (buyerId) q = q.eq('buyer_id', buyerId);
  if (orgId) q = q.eq('organization_id', orgId);
  const { data } = await q;
  if (!data?.length) return <Empty>Aucun dossier pour l&apos;instant.</Empty>;
  return (
    <div className="scroll-x card">
      <table className="tbl">
        <thead><tr><th>Annonce</th><th>Étape</th><th>Dernière activité</th><th /></tr></thead>
        <tbody>
          {data.map((d) => {
            const l = Array.isArray(d.listing) ? d.listing[0] : d.listing;
            return (
              <tr key={d.id}>
                <td><strong>{l?.ref_code}</strong> {l?.title?.fr}</td>
                <td><StatusBadge code={d.closed_at ? 'annule' : d.current_step_code} label={d.closed_at ? 'clos' : undefined} /></td>
                <td className="small">{dateFr(d.last_activity_at)}</td>
                <td><Link className="btn btn-o btn-s" href={`${base}/${d.id}`}>Ouvrir</Link></td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
