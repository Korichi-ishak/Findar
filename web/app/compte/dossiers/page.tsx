import { DossierList } from '@/components/DossierList';
import { PageHead } from '@/components/Notice';
import { getViewer } from '@/lib/session';

export default async function Page() {
  const viewer = (await getViewer())!;
  return (<><PageHead title="Mes demandes et visites" /><DossierList base="/compte/dossiers" buyerId={viewer.id} /></>);
}
