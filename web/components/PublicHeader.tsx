import Link from 'next/link';
import { Logo } from '@/components/Logo';
import { setLocale } from '@/app/actions/locale';
import { getLocale } from '@/lib/i18n';
import { getViewer } from '@/lib/session';
import { PUBLIC_NAV } from '@/lib/routes';

export async function PublicHeader() {
  const [viewer, locale] = await Promise.all([getViewer(), getLocale()]);
  return (
    <header className="hdr">
      <div className="wrap hdr-in">
        <Link href="/" aria-label="Findar, accueil" style={{ textDecoration: 'none' }}>
          <Logo />
        </Link>
        <nav className="nav" aria-label="Navigation principale">
          {PUBLIC_NAV.map((n) => (
            <Link key={n.href} href={n.href} style={{ textDecoration: 'none' }}>
              {n.label}
            </Link>
          ))}
        </nav>
        <div className="hdr-r">
          <form action={setLocale} className="lang">
            {(['fr', 'ar', 'en'] as const).map((l) => (
              <button key={l} name="locale" value={l} aria-pressed={locale === l}>
                {l.toUpperCase()}
              </button>
            ))}
          </form>
          <Link className="btn btn-p btn-s" href="/espace/annonces/nouvelle">Publier</Link>
          <details className="mnav">
            <summary className="icon-btn" aria-label="Menu">
              <svg className="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7h16M4 12h16M4 17h16" /></svg>
            </summary>
            <div className="mnav-panel">
              {PUBLIC_NAV.map((n) => <Link key={n.href} href={n.href}>{n.label}</Link>)}
              <Link href="/espace/annonces/nouvelle">Publier une annonce</Link>
              <Link href={viewer ? '/compte' : '/connexion'}>{viewer ? 'Mon espace' : 'Connexion'}</Link>
            </div>
          </details>
          {viewer ? (
            <Link className="btn btn-o btn-s" href={viewer.spaces.includes('admin') ? '/admin' : viewer.spaces.includes('pro') ? '/pro' : '/compte'}>
              Mon espace
            </Link>
          ) : (
            <Link className="btn btn-o btn-s" href="/connexion">Connexion</Link>
          )}
        </div>
      </div>
    </header>
  );
}
