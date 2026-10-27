import Link from 'next/link';
import { getCommunes } from '@/lib/api/listings';
import { getLocale, tr } from '@/lib/i18n';
import { NotConfigured } from '@/components/Notice';

export const metadata = { title: 'Prix au m² à Alger' };

export default async function Prices() {
  const [communes, locale] = await Promise.all([getCommunes(), getLocale()]);
  return (
    <div className="wrap sec stack" style={{ gap: 20 }}>
      <h1 className="h-l">Prix au m² par commune</h1>
      <p className="muted">Calculés sur les annonces vérifiées. Une moyenne n&apos;est publiée qu&apos;à partir de 5 biens.</p>
      <NotConfigured />
      <div className="row" style={{ gap: 8 }}>
        {communes.map((c) => <Link key={c.slug} className="chip" href={`/prix/${c.slug}`} style={{ textDecoration: 'none' }}>{tr(c.label, locale)}</Link>)}
      </div>
    </div>
  );
}
