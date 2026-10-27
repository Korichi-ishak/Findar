import type { Metadata } from 'next';
import { NotConfigured } from '@/components/Notice';
import { isSupabaseConfigured } from '@/lib/env';
import { OtpForm } from './OtpForm';

export const metadata: Metadata = { title: 'Connexion' };

export default async function Login({ searchParams }: { searchParams: Promise<{ next?: string }> }) {
  const { next } = await searchParams;
  const safeNext = next?.startsWith('/') && !next.startsWith('//') ? next : '/compte';
  return (
    <div className="wrap sec" style={{ maxWidth: 460 }}>
      <div className="card pad-l stack" style={{ gap: 18 }}>
        <h1 className="h-l">Connexion</h1>
        <p className="muted">Un seul compte pour chercher, publier et suivre vos visites.</p>
        <NotConfigured />
        <OtpForm next={safeNext} configured={isSupabaseConfigured} />
      </div>
    </div>
  );
}
