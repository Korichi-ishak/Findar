import { ListingForm } from '@/components/ListingForm';
import { PageHead } from '@/components/Notice';
import { getViewer, proOrg } from '@/lib/session';

export default async function Page() {
  const org = proOrg((await getViewer())!);
  return (<><PageHead title="Nouvelle annonce" /><ListingForm back="/pro" orgId={org?.organization_id} /></>);
}
