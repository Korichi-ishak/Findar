import 'server-only';
import { cookies } from 'next/headers';
import type { Label, Locale } from '@/types/api';

export const LOCALES: Locale[] = ['fr', 'ar', 'en'];
export const LOCALE_COOKIE = 'findar_locale';

export async function getLocale(): Promise<Locale> {
  const v = (await cookies()).get(LOCALE_COOKIE)?.value;
  return LOCALES.includes(v as Locale) ? (v as Locale) : 'fr';
}

export const dirOf = (l: Locale) => (l === 'ar' ? 'rtl' : 'ltr');

/** Libellé multilingue venant de la base, avec repli sur le français. */
export const tr = (label: Partial<Label> | null | undefined, l: Locale) => label?.[l] || label?.fr || '';
