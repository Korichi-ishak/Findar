import { SpaceShell } from '@/components/SpaceShell';
import { proOrg, requireSpace } from '@/lib/session';

export default async function Layout({ children }: { children: React.ReactNode }) {
  const viewer = await requireSpace('pro', '/pro');
  const org = proOrg(viewer);
  return <SpaceShell space="pro" viewer={viewer} sub={org ? `${org.name} · ${org.role_code}` : undefined}>{children}</SpaceShell>;
}
