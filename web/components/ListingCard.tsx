import Link from 'next/link';
import { photoUrl } from '@/lib/media';
import { priceMain, priceSub } from '@/lib/format';
import { tr } from '@/lib/i18n';
import type { ListingPublic, Locale } from '@/types/api';

export function ListingCard({ l, locale }: { l: ListingPublic; locale: Locale }) {
  const img = photoUrl(l.cover_path);
  const facts = [l.rooms ? `F${l.rooms}` : null, l.surface_m2 ? `${Number(l.surface_m2)} m²` : null, tr(l.commune_label, locale)]
    .filter(Boolean)
    .join(' · ');
  return (
    <Link href={`/annonce/${l.ref_code}`} className="lc" style={{ textDecoration: 'none' }}>
      <div className="lc-img">
        {img ? <img src={img} alt="" loading="lazy" /> : null}
        <div className="lc-tags">
          {l.is_sponsored && <span className="badge b-white">Sponsorisé</span>}
          {l.has_tour && <span className="badge b-navy">Visite 360°</span>}
          {l.status_code === 'reservee' && <span className="badge b-orange">Réservée</span>}
        </div>
      </div>
      <div className="lc-b">
        <span className="price num">{priceMain(l, locale)}</span>
        <span className="price-da">{priceSub(l.price_dzd, locale)}</span>
        <span className="facts">{facts}</span>
        <div className="lc-foot">
          <span>{l.advertiser.kind === 'particulier' ? 'Particulier vérifié' : l.advertiser.name}</span>
          {l.verified_at && <span className="ver">✓ Vérifié</span>}
        </div>
      </div>
    </Link>
  );
}
