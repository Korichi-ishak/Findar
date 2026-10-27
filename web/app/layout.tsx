import type { Metadata } from 'next';
import { dirOf, getLocale } from '@/lib/i18n';
import './globals.css';

export const metadata: Metadata = {
  title: { default: 'Findar · Immobilier vérifié à Alger', template: '%s · Findar' },
  description: 'Acheter, louer, estimer à Alger. Chaque annonce est vérifiée par un agent Findar avant sa publication.',
};

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const locale = await getLocale();
  return (
    <html lang={locale} dir={dirOf(locale)}>
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        <link
          rel="stylesheet"
          href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&family=Readex+Pro:wght@400;500;600;700&display=swap"
        />
      </head>
      <body>{children}</body>
    </html>
  );
}
