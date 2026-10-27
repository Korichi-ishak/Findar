import Link from 'next/link';
import { createClient } from '@/lib/supabase/server';
import { isSupabaseConfigured } from '@/lib/env';
import { NotConfigured } from '@/components/Notice';

export const metadata = { title: 'Agences vérifiées' };

export default async function Agencies() {
  const orgs = isSupabaseConfigured
    ? (await (await createClient()).from('organization').select('name, slug, kind_code, response_minutes_avg')
        .in('kind_code', ['agence', 'promoteur']).eq('verification_status', 'verifiee').order('name')).data ?? []
    : [];
  return (
    <div className="wrap sec stack" style={{ gap: 20 }}>
      <h1 className="h-l">Agences et promoteurs vérifiés</h1>
      <NotConfigured />
      {orgs.length ? (
        <div className="grid g3">{orgs.map((o) => (
          <Link key={o.slug} href={`/agences/${o.slug}`} className="card pad stack" style={{ textDecoration: 'none' }}>
            <strong>{o.name}</strong>
            <span className="small muted">{o.kind_code === 'promoteur' ? 'Promoteur' : 'Agence'}{o.response_minutes_avg ? ` · répond en ~${o.response_minutes_avg} min` : ''}</span>
          </Link>))}</div>
      ) : <div className="empty">Aucune agence vérifiée pour l&apos;instant.</div>}
    </div>
  );
}
