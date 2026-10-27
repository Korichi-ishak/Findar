'use client';

export default function Error({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <main className="wrap sec stack" style={{ maxWidth: 560 }}>
      <h1 className="h-l">Quelque chose n&apos;a pas marché</h1>
      <p className="muted">{error.message}</p>
      <button className="btn btn-d" onClick={reset}>Réessayer</button>
    </main>
  );
}
