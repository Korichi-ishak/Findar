import Link from 'next/link';
import { Empty, PageHead } from '@/components/Notice';
import { StatusBadge } from '@/components/StatusBadge';
import { dateFr } from '@/lib/format';
import { createClient } from '@/lib/supabase/server';
import { getViewer, proOrg } from '@/lib/session';

export default async function Page() {
  const org = proOrg((await getViewer())!);
  const supabase = await createClient();
  const { data } = await supabase.from('visit')
    .select('id, starts_at, status, dossier_id, dossier!inner(organization_id, listing:listing_id(ref_code))')
    .eq('dossier.organization_id', org?.organization_id ?? '').in('status', ['proposee', 'confirmee'])
    .gte('starts_at', new Date().toISOString()).order('starts_at');
  return (
    <>
      <PageHead title="Agenda des visites" />
      {data?.length ? (
        <div className="card">{data.map((v) => {
          const d = Array.isArray(v.dossier) ? v.dossier[0] : v.dossier;
          const l = d && (Array.isArray(d.listing) ? d.listing[0] : d.listing);
          return (
            <Link key={v.id} href={`/pro/demandes/${v.dossier_id}`} className="pad row between" style={{ textDecoration: 'none', borderBottom: '1px solid var(--line-2)' }}>
              <span><strong>{dateFr(v.starts_at)}</strong> · {l?.ref_code}</span><StatusBadge code={v.status} />
            </Link>);
        })}</div>
      ) : <Empty>Aucune visite à venir.</Empty>}
    </>
  );
}
