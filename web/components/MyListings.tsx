import Link from 'next/link';
import { StatusBadge } from '@/components/StatusBadge';
import { Empty } from '@/components/Notice';
import { priceMain } from '@/lib/format';
import { createClient } from '@/lib/supabase/server';

export async function MyListings({ orgId, base }: { orgId?: string; base: string }) {
  if (!orgId) return <Empty>Aucune annonce. Déposez la première : elle sera vérifiée sous 48 h ouvrées.</Empty>;
  const supabase = await createClient();
  const [{ data }, { data: statuses }] = await Promise.all([
    supabase.from('listing').select('id, ref_code, title, status_code, price_dzd, category_code, metadata, updated_at')
      .eq('organization_id', orgId).is('deleted_at', null).order('updated_at', { ascending: false }),
    supabase.from('ref_listing_status').select('code, label'),
  ]);
  const label = Object.fromEntries((statuses ?? []).map((s) => [s.code, s.label.fr as string]));
  if (!data?.length) return <Empty>Aucune annonce pour l&apos;instant.</Empty>;
  return (
    <div className="scroll-x card">
      <table className="tbl">
        <thead><tr><th>Réf.</th><th>Annonce</th><th>Prix</th><th>Statut</th><th /></tr></thead>
        <tbody>{data.map((l) => (
          <tr key={l.id}>
            <td><strong>{l.ref_code}</strong></td>
            <td>{l.title?.fr || '—'} {l.metadata?.inactivity_asked_at && <span className="badge b-warn">Toujours disponible ?</span>}</td>
            <td className="num">{priceMain(l)}</td>
            <td><StatusBadge code={l.status_code} label={label[l.status_code]} /></td>
            <td><Link className="btn btn-o btn-s" href={`${base}/annonces/${l.id}`}>Gérer</Link></td>
          </tr>))}</tbody>
      </table>
    </div>
  );
}
