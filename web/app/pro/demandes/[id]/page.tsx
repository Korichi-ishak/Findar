import { DossierView } from '@/components/DossierView';
import { getViewer } from '@/lib/session';

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const [{ id }, viewer] = await Promise.all([params, getViewer()]);
  return <DossierView id={id} viewer={viewer!} />;
}
