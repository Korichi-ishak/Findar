import { createListing } from '@/app/actions/listing';
import { getCommunes, getRefs } from '@/lib/api/listings';
import { getLocale, tr } from '@/lib/i18n';

/** Formulaire de dépôt commun au particulier et aux pros (orgId = organisation pro). */
export async function ListingForm({ back, orgId }: { back: string; orgId?: string }) {
  const [locale, categories, types, communes] = await Promise.all([getLocale(), getRefs('ref_category'), getRefs('ref_property_type'), getCommunes()]);
  return (
    <form action={createListing} className="stack" style={{ gap: 20 }}>
      <input type="hidden" name="back" value={back} />
      {orgId && <input type="hidden" name="org_id" value={orgId} />}
      <section className="card pad stack">
        <h2 className="h-s">Le bien</h2>
        <div className="filters">
          <div className="field"><label htmlFor="category">Annonce</label>
            <select id="category" name="category" className="inp" required>{categories.map((c) => <option key={c.code} value={c.code}>{tr(c.label, locale)}</option>)}</select></div>
          <div className="field"><label htmlFor="type">Type</label>
            <select id="type" name="type" className="inp" required>{types.map((c) => <option key={c.code} value={c.code}>{tr(c.label, locale)}</option>)}</select></div>
          <div className="field"><label htmlFor="rooms">Pièces (F)</label><input id="rooms" name="rooms" className="inp num" inputMode="numeric" /></div>
          <div className="field"><label htmlFor="surface">Surface (m²)</label><input id="surface" name="surface" className="inp num" inputMode="decimal" /></div>
          <div className="field"><label htmlFor="floor">Étage</label><input id="floor" name="floor" className="inp num" inputMode="numeric" /></div>
        </div>
      </section>
      <section className="card pad stack">
        <h2 className="h-s">Prix</h2>
        <div className="row" style={{ alignItems: 'end' }}>
          <div className="field" style={{ flex: 1, minWidth: 180 }}><label htmlFor="price">Montant</label><input id="price" name="price" className="inp num" inputMode="decimal" placeholder="ex. 320" /></div>
          <div className="field"><label htmlFor="price_unit">Unité (obligatoire)</label>
            <select id="price_unit" name="price_unit" className="inp" required defaultValue="">
              <option value="" disabled>Choisir</option>
              <option value="millions">millions (centimes)</option>
              <option value="milliards">milliards (centimes)</option>
              <option value="DA">DA</option>
            </select></div>
        </div>
        <p className="hint">« 320 millions » = 3 200 000 DA. Le prix est toujours enregistré en DA.</p>
      </section>
      <section className="card pad stack">
        <h2 className="h-s">Adresse</h2>
        <p className="hint">L&apos;adresse exacte reste privée : le public voit la commune et une position floutée à 150 m.</p>
        <div className="filters">
          <div className="field"><label htmlFor="commune">Commune</label>
            <select id="commune" name="commune" className="inp" required>{communes.map((c) => <option key={c.slug} value={c.slug}>{tr(c.label, locale)}</option>)}</select></div>
          <div className="field"><label htmlFor="quartier">Quartier</label><input id="quartier" name="quartier" className="inp" /></div>
          <div className="field" style={{ gridColumn: 'span 2' }}><label htmlFor="address">Adresse exacte</label><input id="address" name="address" className="inp" required /></div>
        </div>
      </section>
      <section className="card pad stack">
        <h2 className="h-s">Présentation</h2>
        <div className="field"><label htmlFor="title">Titre</label><input id="title" name="title" className="inp" maxLength={90} /></div>
        <div className="field"><label htmlFor="description">Description</label><textarea id="description" name="description" className="inp" rows={5} /></div>
      </section>
      <section className="card pad stack">
        <h2 className="h-s">Vérification avant publication</h2>
        <label className="row"><input type="radio" name="method" value="visio" defaultChecked /> Appel vidéo avec un agent Findar (gratuit)</label>
        <label className="row"><input type="radio" name="method" value="visite_360" /> Visite 360° par un agent Findar (payante pour les particuliers)</label>
      </section>
      <div className="row">
        <button className="btn btn-p" name="submit" value="1">Envoyer en vérification</button>
        <button className="btn btn-o" name="submit" value="0">Garder en brouillon</button>
      </div>
    </form>
  );
}
