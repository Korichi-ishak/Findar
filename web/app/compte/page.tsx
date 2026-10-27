import Link from 'next/link';
import { DossierList } from '@/components/DossierList';
import { PageHead } from '@/components/Notice';
import { getViewer } from '@/lib/session';

export default async function Dashboard() {
  const viewer = (await getViewer())!;
  return (
    <>
      <PageHead title={`Bonjour${viewer.fullName ? ' ' + viewer.fullName.split(' ')[0] : ''}`}>
        <Link className="btn btn-d btn-s" href="/recherche">Chercher un bien</Link>
      </PageHead>
      <h2 className="h-s">Vos demandes en cours</h2>
      <DossierList base="/compte/dossiers" buyerId={viewer.id} />
    </>
  );
}
