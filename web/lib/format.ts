import type { Locale } from '@/types/api';

const nf = (n: number, l: Locale, d = 0) =>
  new Intl.NumberFormat(l === 'en' ? 'en-US' : 'fr-FR', { maximumFractionDigits: d }).format(n);

/** 32 000 000 DA → « 320 millions » (centimes, l'unité parlée en Algérie). */
export function centimes(da: number, l: Locale = 'fr') {
  const c = da * 100;
  if (c >= 1e9) {
    const v = c / 1e9;
    return l === 'ar' ? `${nf(v, l, 2)} مليار` : `${nf(v, l, 2)} ${v >= 2 ? 'milliards' : 'milliard'}`;
  }
  const v = c / 1e6;
  return l === 'ar' ? `${nf(v, l, 1)} مليون` : `${nf(v, l, 1)} ${v >= 2 ? 'millions' : 'million'}`;
}

export const dzd = (da: number, l: Locale = 'fr') =>
  l === 'ar' ? `${nf(da, l)} دج` : l === 'en' ? `DZD ${nf(da, l)}` : `${nf(da, l)} DA`;

const RENT = new Set(['location', 'location_vacances']);

export function priceMain(p: { price_dzd: number | null; price_is_from?: boolean; category_code: string }, l: Locale = 'fr') {
  if (p.price_dzd == null) return l === 'ar' ? 'السعر عند الطلب' : 'Prix sur demande';
  const from = p.price_is_from ? (l === 'ar' ? 'ابتداء من ' : l === 'en' ? 'From ' : 'À partir de ') : '';
  const per = RENT.has(p.category_code) ? (l === 'ar' ? ' / شهر' : l === 'en' ? ' / month' : ' / mois') : '';
  return from + (l === 'en' ? dzd(p.price_dzd, l) : centimes(p.price_dzd, l)) + per;
}

export const priceSub = (da: number | null, l: Locale = 'fr') =>
  da == null ? '' : l === 'en' ? `${centimes(da, l)} centimes` : dzd(da, l);

/** Saisie : l'unité est obligatoire. Renvoie toujours des DA. */
export function toDzd(value: number, unit: 'DA' | 'centimes' | 'millions' | 'milliards') {
  switch (unit) {
    case 'DA': return Math.round(value);
    case 'centimes': return Math.round(value / 100);
    case 'millions': return Math.round((value * 1e6) / 100);   // « 320 millions » de centimes
    case 'milliards': return Math.round((value * 1e9) / 100);
  }
}

export const dateFr = (iso: string | null | undefined) =>
  iso ? new Intl.DateTimeFormat('fr-FR', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Africa/Algiers' }).format(new Date(iso)) : '—';
