'use server';
import { cookies } from 'next/headers';
import { LOCALE_COOKIE, LOCALES } from '@/lib/i18n';
import type { Locale } from '@/types/api';

export async function setLocale(formData: FormData) {
  const l = String(formData.get('locale')) as Locale;
  if (!LOCALES.includes(l)) return;
  (await cookies()).set(LOCALE_COOKIE, l, { path: '/', maxAge: 60 * 60 * 24 * 365, sameSite: 'lax' });
}
