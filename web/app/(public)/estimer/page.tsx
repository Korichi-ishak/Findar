import { Shell } from '@/components/Notice';

export const metadata = { title: 'Estimer mon bien' };

export default function Estimate() {
  return (
    <div className="wrap sec">
      <Shell title="Estimer mon bien" proto="estimer">
        <div className="card pad stack">
          <p>Règle déjà en base (réglages <code>estimate.*</code>) : une fourchette s&apos;affiche seulement avec au moins 8 comparables et une précision testée de 15 % ou mieux. Sinon : le prix au m² de la commune, ou « pas assez de données ».</p>
          <p className="muted small">Chaque calcul est enregistré dans <code>estimate_run</code> (version du modèle, comparables) pour pouvoir être rejoué. Après l&apos;estimation : publier l&apos;annonce ou être mis en relation avec une agence.</p>
        </div>
      </Shell>
    </div>
  );
}
