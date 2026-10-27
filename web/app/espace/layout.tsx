import { SpaceShell } from '@/components/SpaceShell';
import { requireSpace } from '@/lib/session';

export default async function Layout({ children }: { children: React.ReactNode }) {
  const viewer = await requireSpace('espace', '/espace');
  return <SpaceShell space="espace" viewer={viewer} sub="2 annonces actives maximum">{children}</SpaceShell>;
}
