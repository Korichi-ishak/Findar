import { SpaceShell } from '@/components/SpaceShell';
import { requireSpace } from '@/lib/session';

export default async function Layout({ children }: { children: React.ReactNode }) {
  const viewer = await requireSpace('admin', '/admin');
  return <SpaceShell space="admin" viewer={viewer} sub={viewer.staffRoles.join(' · ')}>{children}</SpaceShell>;
}
