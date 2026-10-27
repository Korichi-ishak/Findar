import { notFound } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { isSupabaseConfigured } from '@/lib/env';
import { dzd } from '@/lib/format';
import { getLocale, tr } from '@/lib/i18n';
import { NotConfigured } from '@/components/Notice';

type Row = { month: string; median_price_m2: number; n: number };

export default async function CommunePrices({ params }: { params: Promise<{ commune: string }> }) {
  const { commune } = await params;
  const locale = await getLocale();
  if (!isSupabaseConfigured) return <div className="wrap sec"><NotConfigured /></div>;
  const supabase = await createClient();
  const [{ data: c }, { data: rows }] = await Promise.all([
    supabase.from('commune').select('label').eq('slug', commune).maybeSingle(),
    supabase.rpc('market_price_m2', { p_commune: commune, p_category: 'vente', p_months: 12 }),
  ]);
  if (!c) notFound();
  const series = (rows ?? []) as Row[];
  return (
    <div className="wrap sec stack" style={{ gap: 20 }}>
      <h1 className="h-l">Prix au m² · {tr(c.label, locale)}</h1>
      {series.length ? (
        <table className="tbl card">
          <thead><tr><th>Mois</th><th>Médiane / m²</th><th>Biens</th></tr></thead>
          <tbody>{series.map((r) => <tr key={r.month}><td>{r.month.slice(0, 7)}</td><td className="num">{dzd(r.median_price_m2, locale)}</td><td className="num">{r.n}</td></tr>)}</tbody>
        </table>
      ) : (
        <div className="empty">Pas assez de données pour publier un prix fiable dans cette commune.</div>
      )}
    </div>
  );
}
