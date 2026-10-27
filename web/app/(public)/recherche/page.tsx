import type { Metadata } from 'next';
import Link from 'next/link';
import { ListingCard } from '@/components/ListingCard';
import { ErrorNote, NotConfigured } from '@/components/Notice';
import { filtersFromParams, getCommunes, getRefs, searchListings } from '@/lib/api/listings';
import { getLocale, tr } from '@/lib/i18n';

export const metadata: Metadata = { title: 'Rechercher' };

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

export default async function Search({ searchParams }: Props) {
  const params = await searchParams;
  const { filters, sort, page } = filtersFromParams(params);
  const [locale, { rows, error }, categories, types, pois, communes] = await Promise.all([
    getLocale(), searchListings(filters, sort, page), getRefs('ref_category'), getRefs('ref_property_type'), getRefs('ref_poi_kind'), getCommunes(),
  ]);
  const v = (k: string) => (typeof params[k] === 'string' ? (params[k] as string) : '');
  const near = new Set([params.proche ?? []].flat());

  return (
    <div className="wrap sec stack" style={{ gap: 24, paddingTop: 28 }}>
      <NotConfigured />
      {/* Formulaire GET : l'URL est la source de vérité (partage, retour arrière, alertes). */}
      <form className="card pad stack" style={{ gap: 16 }}>
        <div className="filters">
          <div className="field"><label htmlFor="category">Je cherche</label>
            <select id="category" name="category" className="inp" defaultValue={v('category')}>
              <option value="">Tout</option>
              {categories.map((c) => <option key={c.code} value={c.code}>{tr(c.label, locale)}</option>)}
            </select></div>
          <div className="field"><label htmlFor="types">Type de bien</label>
            <select id="types" name="types" className="inp" defaultValue={v('types')}>
              <option value="">Tous</option>
              {types.map((c) => <option key={c.code} value={c.code}>{tr(c.label, locale)}</option>)}
            </select></div>
          <div className="field"><label htmlFor="communes">Commune</label>
            <select id="communes" name="communes" className="inp" defaultValue={v('communes')}>
              <option value="">Toute la wilaya</option>
              {communes.map((c) => <option key={c.slug} value={c.slug}>{tr(c.label, locale)}</option>)}
            </select></div>
          <div className="field"><label htmlFor="prix_max">Budget max (DA)</label>
            <input id="prix_max" name="prix_max" className="inp num" inputMode="numeric" defaultValue={v('prix_max')} placeholder="ex. 30000000" /></div>
          <div className="field"><label htmlFor="pieces_min">Pièces min.</label>
            <select id="pieces_min" name="pieces_min" className="inp" defaultValue={v('pieces_min')}>
              <option value="">Indifférent</option>
              {[1, 2, 3, 4, 5].map((n) => <option key={n} value={n}>F{n} et +</option>)}
            </select></div>
          <div className="field"><label htmlFor="tri">Trier</label>
            <select id="tri" name="tri" className="inp" defaultValue={v('tri') || 'recent'}>
              <option value="recent">Plus récentes</option>
              <option value="price_asc">Prix croissant</option>
              <option value="price_desc">Prix décroissant</option>
              <option value="price_m2_asc">Prix au m² croissant</option>
              <option value="surface_desc">Plus grandes</option>
            </select></div>
        </div>
        <div className="row" style={{ gap: 8 }}>
          <label className="chip"><input type="checkbox" name="verifie" value="1" defaultChecked={v('verifie') === '1'} /> Vérifiées 360° ou visio</label>
          <label className="chip"><input type="checkbox" name="tour" value="1" defaultChecked={v('tour') === '1'} /> Avec visite 360°</label>
          {pois.map((p) => (
            <label key={p.code} className="chip">
              <input type="checkbox" name="proche" value={p.code} defaultChecked={near.has(p.code)} /> {tr(p.label, locale)}
            </label>
          ))}
        </div>
        <div className="row"><button className="btn btn-d">Afficher les annonces</button><Link className="btn btn-g" href="/recherche">Effacer</Link></div>
      </form>

      <ErrorNote error={error} />
      <div className="row between">
        <h1 className="h-m">{rows.length} annonce{rows.length > 1 ? 's' : ''}</h1>
        <span className="small muted">Carte Google Maps : à brancher (clé NEXT_PUBLIC_GOOGLE_MAPS_KEY)</span>
      </div>
      {rows.length ? (
        <div className="grid g4">{rows.map((l) => <ListingCard key={l.id} l={l} locale={locale} />)}</div>
      ) : (
        <div className="empty">Aucune annonce ne correspond. Élargissez la commune ou le budget, ou créez une alerte.</div>
      )}
    </div>
  );
}
