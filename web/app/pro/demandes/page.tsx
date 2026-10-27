import { DossierList } from '@/components/DossierList';
import { PageHead } from '@/components/Notice';
import { getViewer, proOrg } from '@/lib/session';

export default async function Page() {
  const org = proOrg((await getViewer())!);
  return (<><PageHead title="Boîte de demandes commune" />
    <p className="small muted">Tous les membres de l&apos;agence voient les mêmes dossiers. Le premier qui répond prend le dossier.</p>
    <DossierList base="/pro/demandes" orgId={org?.organization_id} /></>);
}
