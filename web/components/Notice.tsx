import { isSupabaseConfigured } from '@/lib/env';

export function NotConfigured() {
  if (isSupabaseConfigured) return null;
  return (
    <p className="notice warn">
      Base non branchée : remplir <code>NEXT_PUBLIC_SUPABASE_URL</code> et <code>NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY</code> dans{' '}
      <code>web/.env.local</code>. Les pages s&apos;affichent, sans données.
    </p>
  );
}

/** Écran posé mais pas encore construit : renvoie vers la maquette du prototype. */
export function Shell({ title, proto, children }: { title: string; proto: string; children?: React.ReactNode }) {
  return (
    <div className="stack" style={{ gap: 16 }}>
      <div className="page-h">
        <h1 className="h-l">{title}</h1>
        <span className="todo">À construire · maquette « {proto} »</span>
      </div>
      {children ?? <div className="empty">Écran prévu dans la V0. La maquette est dans le prototype cliquable, écran « {proto} ».</div>}
    </div>
  );
}

export function PageHead({ title, children }: { title: string; children?: React.ReactNode }) {
  return (
    <div className="page-h">
      <h1 className="h-l">{title}</h1>
      {children}
    </div>
  );
}

export function Empty({ children }: { children: React.ReactNode }) {
  return <div className="empty">{children}</div>;
}

export function ErrorNote({ error }: { error: { message: string } | null }) {
  if (!error) return null;
  return <p className="notice warn">Erreur de la base : {error.message}</p>;
}
