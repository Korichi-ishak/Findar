import Link from 'next/link';
import { MyListings } from '@/components/MyListings';
import { PageHead } from '@/components/Notice';
import { getViewer, personalOrg } from '@/lib/session';

export default async function Page() {
  const viewer = (await getViewer())!;
  return (
    <>
      <PageHead title="Mes annonces"><Link className="btn btn-p btn-s" href="/espace/annonces/nouvelle">Déposer une annonce</Link></PageHead>
      <MyListings orgId={personalOrg(viewer)?.organization_id} base="/espace" />
    </>
  );
}
