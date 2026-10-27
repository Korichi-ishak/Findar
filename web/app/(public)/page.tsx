import Link from 'next/link';
import { ListingCard } from '@/components/ListingCard';
import { NotConfigured } from '@/components/Notice';
import { searchListings } from '@/lib/api/listings';
import { getLocale } from '@/lib/i18n';

export default async function Home() {
  const [locale, { rows }] = await Promise.all([getLocale(), searchListings({}, 'recent', 1, 8)]);
  return (
    <>
      <section className="sec" style={{ background: 'var(--navy)', color: 'var(--porc)' }}>
        <div className="wrap stack" style={{ gap: 20 }}>
          <p className="eyebrow" style={{ color: 'var(--orange)' }}>Alger · annonces vérifiées</p>
          <h1 className="h-xl" style={{ maxWidth: 820 }}>Chaque bien est vérifié par un agent Findar avant d&apos;être publié.</h1>
          <form action="/recherche" className="hero-search">
            <select name="category" className="inp" style={{ width: 'auto' }} defaultValue="vente" aria-label="Type de recherche">
              <option value="vente">Acheter</option>
              <option value="location">Louer</option>
              <option value="neuf">Neuf</option>
              <option value="terrain">Terrain</option>
            </select>
            <input name="q" className="inp" style={{ flex: 1, minWidth: 0 }} placeholder="Commune, quartier ou référence" aria-label="Recherche" />
            <button className="btn btn-p">Rechercher</button>
          </form>
        </div>
      </section>
      <section className="sec wrap">
        <NotConfigured />
        <div className="sec-t">
          <h2 className="h-l">Dernières annonces vérifiées</h2>
          <Link className="btn btn-o btn-s" href="/recherche">Tout voir</Link>
        </div>
        {rows.length ? (
          <div className="grid g4">{rows.map((l) => <ListingCard key={l.id} l={l} locale={locale} />)}</div>
        ) : (
          <div className="empty">Pas encore d&apos;annonce publiée.</div>
        )}
      </section>
    </>
  );
}
