import Link from 'next/link';

export default function NotFound() {
  return (
    <main className="wrap sec stack" style={{ maxWidth: 560 }}>
      <h1 className="h-l">Page introuvable</h1>
      <p className="muted">L&apos;annonce a peut-être été retirée ou vendue.</p>
      <Link className="btn btn-d" href="/recherche">Voir les annonces</Link>
    </main>
  );
}
