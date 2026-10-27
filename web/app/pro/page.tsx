import Link from 'next/link';
import { PageHead } from '@/components/Notice';
import { createClient } from '@/lib/supabase/server';
import { getViewer, proOrg } from '@/lib/session';

export default async function Page() {
  const org = proOrg((await getViewer())!)!;
  const supabase = await createClient();
  const [listings, verif, dossiers, visits] = await Promise.all([
    supabase.from('listing').select('id', { count: 'exact', head: true }).eq('organization_id', org.organization_id).eq('status_code', 'disponible'),
    supabase.from('listing').select('id', { count: 'exact', head: true }).eq('organization_id', org.organization_id).in('status_code', ['en_verification', 'verification_bien', 'a_corriger']),
    supabase.from('dossier').select('id', { count: 'exact', head: true }).eq('organization_id', org.organization_id).is('closed_at', null),
    supabase.from('visit').select('id, dossier!inner(organization_id)', { count: 'exact', head: true })
      .eq('dossier.organization_id', org.organization_id).eq('status', 'proposee'),
  ]);
  const tiles = [
    ['Annonces en ligne', listings.count, '/pro/annonces'],
    ['En vérification', verif.count, '/pro/annonces'],
    ['Dossiers ouverts', dossiers.count, '/pro/demandes'],
    ['Visites à confirmer', visits.count, '/pro/agenda'],
  ] as const;
  return (
    <>
      <PageHead title={org.name}><Link className="btn btn-p btn-s" href="/pro/annonces/nouvelle">Nouvelle annonce</Link></PageHead>
      <div className="grid g4">{tiles.map(([t, n, href]) => (
        <Link key={t} href={href} className="card pad stack" style={{ textDecoration: 'none', gap: 4 }}>
          <span className="small muted">{t}</span><span className="h-l num">{n ?? 0}</span>
        </Link>))}</div>
    </>
  );
}
