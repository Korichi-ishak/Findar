import { DossierList } from '@/components/DossierList';
import { Empty, PageHead } from '@/components/Notice';
import { getViewer, personalOrg } from '@/lib/session';

export default async function Page() {
  const org = personalOrg((await getViewer())!);
  return (<><PageHead title="Demandes reçues" />{org ? <DossierList base="/espace/demandes" orgId={org.organization_id} /> : <Empty>Pas encore d&apos;annonce publiée.</Empty>}</>);
}
