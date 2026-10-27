import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { contactListing } from '@/app/actions/dossier';
import { getListing } from '@/lib/api/listings';
import { dateFr, priceMain, priceSub, dzd } from '@/lib/format';
import { getLocale, tr } from '@/lib/i18n';
import { photoUrl } from '@/lib/media';
import { createClient } from '@/lib/supabase/server';

type Props = { params: Promise<{ ref: string }>; searchParams: Promise<{ erreur?: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const l = await getListing((await params).ref);
  return { title: l ? `${l.title.fr ?? l.ref_code}` : 'Annonce' };
}

export default async function ListingPage({ params, searchParams }: Props) {
  const [{ ref }, { erreur }, locale] = await Promise.all([params, searchParams, getLocale()]);
  const l = await getListing(ref);
  if (!l) notFound();

  const supabase = await createClient();
  const [media, poi, tour] = await Promise.all([
    supabase.from('listing_media').select('storage_path, room_label, kind').eq('listing_id', l.id).order('sort'),
    supabase.from('listing_poi').select('poi_kind_code, distance_m, name').eq('listing_id', l.id).order('distance_m'),
    supabase.from('tour').select('public_url').eq('listing_id', l.id).not('public_url', 'is', null).maybeSingle(),
  ]);
  const canContact = l.status_code === 'disponible';

  return (
    <div className="wrap sec stack" style={{ gap: 24, paddingTop: 28 }}>
      <div className="grid g3" style={{ gridTemplateColumns: 'repeat(auto-fill,minmax(min(220px,100%),1fr))' }}>
        {(media.data ?? []).filter((m) => m.kind === 'photo').slice(0, 5).map((m) => (
          <img key={m.storage_path} src={photoUrl(m.storage_path)!} alt={m.room_label ?? ''} style={{ width: '100%', aspectRatio: '3/2', objectFit: 'cover', borderRadius: 12 }} />
        ))}
        {!media.data?.length && <div className="empty">Photos à venir</div>}
      </div>

      <div className="acct" style={{ gridTemplateColumns: 'minmax(0,1fr) 340px', paddingBlock: 0 }}>
        <div className="stack" style={{ gap: 20 }}>
          <div className="stack" style={{ gap: 6 }}>
            <span className="price num" style={{ fontSize: 32 }}>{priceMain(l, locale)}</span>
            <span className="price-da">{priceSub(l.price_dzd, locale)}{l.price_m2_dzd ? ` · ${dzd(l.price_m2_dzd, locale)} / m²` : ''}</span>
            <h1 className="h-m">{tr(l.title, locale) || `Réf. ${l.ref_code}`}</h1>
            <p className="muted">{[l.quartier, tr(l.commune_label, locale)].filter(Boolean).join(', ')} · position approximative (± 150 m)</p>
          </div>
          <dl className="kv card pad">
            {l.rooms != null && <div><dt>Pièces</dt><dd>F{l.rooms}</dd></div>}
            {l.surface_m2 != null && <div><dt>Surface</dt><dd>{Number(l.surface_m2)} m²</dd></div>}
            {l.floor != null && <div><dt>Étage</dt><dd>{l.floor}{l.floors_total ? ` / ${l.floors_total}` : ''}</dd></div>}
            <div><dt>Référence</dt><dd>{l.ref_code}</dd></div>
            <div><dt>Vérifiée</dt><dd>{l.verified_at ? `${l.verified_method_code === 'visite_360' ? '360°' : 'visio'} · ${dateFr(l.verified_at)}` : '—'}</dd></div>
            <div><dt>Disponibilité confirmée</dt><dd>{dateFr(l.last_confirmed_at)}</dd></div>
          </dl>
          {tr(l.description, locale) && <p style={{ whiteSpace: 'pre-line' }}>{tr(l.description, locale)}</p>}
          {tour.data?.public_url && (
            <iframe title="Visite 360°" src={tour.data.public_url} style={{ width: '100%', aspectRatio: '16/9', border: 0, borderRadius: 12 }} allowFullScreen />
          )}
          {!!poi.data?.length && (
            <section className="card pad stack">
              <h2 className="h-s">À proximité</h2>
              <ul className="stack small" style={{ gap: 6, margin: 0, paddingInlineStart: 18 }}>
                {poi.data.map((p) => <li key={p.poi_kind_code}>{p.poi_kind_code} · {p.name ?? ''} · {p.distance_m} m</li>)}
              </ul>
            </section>
          )}
        </div>

        <aside className="card pad stack" style={{ position: 'sticky', top: 96, alignSelf: 'start' }}>
          <strong>{l.advertiser.kind === 'particulier' ? 'Particulier vérifié' : l.advertiser.name}</strong>
          <p className="small muted">Contact uniquement par la messagerie Findar. L&apos;adresse exacte est donnée la veille de la visite confirmée.</p>
          {erreur && <p className="notice warn small">{erreur}</p>}
          {canContact ? (
            <form action={contactListing} className="stack">
              <input type="hidden" name="listing_id" value={l.id} />
              <input type="hidden" name="ref" value={l.ref_code} />
              <button className="btn btn-p">Demander une visite</button>
            </form>
          ) : (
            <p className="notice small">Annonce réservée : rejoignez la liste d&apos;attente pour être prévenu.</p>
          )}
        </aside>
      </div>
    </div>
  );
}
