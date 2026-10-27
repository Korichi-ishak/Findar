import Link from 'next/link';
import { Logo } from '@/components/Logo';
import { SideNav } from '@/components/SideNav';
import { NotConfigured } from '@/components/Notice';
import { SPACES, type Space } from '@/lib/routes';
import { hasStaffRole, type Viewer } from '@/lib/session';
import { signOut } from '@/app/actions/auth';

const LABEL: Record<Space, string> = { compte: 'Acheteur', espace: 'Particulier', pro: 'Pro', admin: 'Findar' };

export function SpaceShell({ space, viewer, sub, children }: { space: Space; viewer: Viewer; sub?: string; children: React.ReactNode }) {
  const items = SPACES[space].items.filter((it) => space !== 'admin' || !it.staff || hasStaffRole(viewer, it.staff));
  return (
    <>
      <header className="hdr">
        <div className="wrap hdr-in">
          <Link href="/" aria-label="Retour au site" style={{ textDecoration: 'none' }}>
            <Logo />
          </Link>
          <nav className="nav" aria-label="Espaces">
            {viewer.spaces.map((s) => (
              <Link key={s} href={`/${s}`} aria-current={s === space ? 'page' : undefined} style={{ textDecoration: 'none' }}>
                {LABEL[s]}
              </Link>
            ))}
          </nav>
          <div className="hdr-r">
            <span className="small muted">{viewer.fullName ?? viewer.email}</span>
            <form action={signOut}>
              <button className="btn btn-o btn-s">Déconnexion</button>
            </form>
          </div>
        </div>
      </header>
      <div className="wrap acct">
        <SideNav title={SPACES[space].title} sub={sub} items={items} />
        <main className="stack" style={{ gap: 20, minWidth: 0 }}>
          <NotConfigured />
          {children}
        </main>
      </div>
    </>
  );
}
