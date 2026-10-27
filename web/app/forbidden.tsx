import Link from 'next/link';

export default function Forbidden() {
  return (
    <main className="wrap sec stack" style={{ maxWidth: 560 }}>
      <h1 className="h-l">Cet espace n&apos;est pas ouvert pour votre compte</h1>
      <p className="muted">Un espace pro s&apos;ouvre après la vérification de l&apos;agence. Le back-office est réservé à l&apos;équipe Findar.</p>
      <Link className="btn btn-d" href="/compte">Revenir à mon compte</Link>
    </main>
  );
}
