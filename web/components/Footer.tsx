import Link from 'next/link';
import { Logo } from '@/components/Logo';

export function Footer() {
  return (
    <footer className="foot">
      <div className="wrap row between" style={{ alignItems: 'start', gap: 32 }}>
        <div className="stack">
          <Logo light />
          <p className="small" style={{ opacity: 0.7, maxWidth: 280 }}>
            Plateforme immobilière d&apos;Alger. Chaque annonce est vérifiée par un agent Findar avant sa publication.
          </p>
        </div>
        <div className="stack small">
          <Link href="/recherche">Rechercher</Link>
          <Link href="/estimer">Estimer mon bien</Link>
          <Link href="/agences">Agences</Link>
        </div>
        <div className="stack small">
          <Link href="/tarifs">Tarifs pros</Link>
          <Link href="/guides">Guides</Link>
          <Link href="/aide">Aide et sécurité</Link>
        </div>
      </div>
    </footer>
  );
}
