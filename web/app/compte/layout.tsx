import { SpaceShell } from '@/components/SpaceShell';
import { requireSpace } from '@/lib/session';

export default async function Layout({ children }: { children: React.ReactNode }) {
  const viewer = await requireSpace('compte', '/compte');
  return <SpaceShell space="compte" viewer={viewer}>{children}</SpaceShell>;
}
