import Link from 'next/link';
import { MyListings } from '@/components/MyListings';
import { PageHead } from '@/components/Notice';
import { getViewer, proOrg } from '@/lib/session';

export default async function Page() {
  const org = proOrg((await getViewer())!);
  return (<><PageHead title="Annonces"><Link className="btn btn-p btn-s" href="/pro/annonces/nouvelle">Nouvelle annonce</Link></PageHead>
    <p className="small muted">Pour chaque annonce : mandat du propriétaire + visite 360° ou appel vidéo, avant publication.</p>
    <MyListings orgId={org?.organization_id} base="/pro" /></>);
}
