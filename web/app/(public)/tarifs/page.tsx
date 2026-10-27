import { createClient } from '@/lib/supabase/server';
import { isSupabaseConfigured } from '@/lib/env';
import { dzd } from '@/lib/format';
import { getLocale, tr } from '@/lib/i18n';
import { NotConfigured } from '@/components/Notice';

export const metadata = { title: 'Tarifs pros' };

export default async function Pricing() {
  const locale = await getLocale();
  const plans = isSupabaseConfigured ? (await (await createClient()).from('plan').select('*').eq('active', true).order('sort')).data ?? [] : [];
  return (
    <div className="wrap sec stack" style={{ gap: 20 }}>
      <h1 className="h-l">Formules pour les agences et promoteurs</h1>
      <NotConfigured />
      <div className="grid g4">{plans.map((p) => (
        <div key={p.code} className="card pad stack">
          <strong className="h-s">{tr(p.label, locale)}</strong>
          <span className="price num">{p.price_dzd == null ? (p.period === 'devis' ? 'Sur devis' : 'Prix à venir') : `${dzd(p.price_dzd, locale)} / ${p.period}`}</span>
        </div>))}</div>
    </div>
  );
}
