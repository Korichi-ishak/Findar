import { redirect } from 'next/navigation';
import { createProOrganization } from '@/app/actions/pro';
import { getCommunes } from '@/lib/api/listings';
import { getLocale, tr } from '@/lib/i18n';
import { getViewer } from '@/lib/session';

export const metadata = { title: 'Inscription agence ou promoteur' };

export default async function Page() {
  const viewer = await getViewer();
  if (!viewer) redirect('/connexion?next=/inscription-pro');
  const [communes, locale] = await Promise.all([getCommunes(), getLocale()]);
  return (
    <div className="wrap sec" style={{ maxWidth: 640 }}>
      <form action={createProOrganization} className="card pad-l stack" style={{ gap: 18 }}>
        <h1 className="h-l">Ouvrir un compte pro</h1>
        <p className="muted">Votre compte est vérifié une fois (RC + agrément pour une agence, RC + permis de construire pour un promoteur), sous 48 h ouvrées. Vos annonces sont ensuite vérifiées une par une.</p>
        <div className="seg" role="radiogroup">
          <label className="chip"><input type="radio" name="kind" value="agence" defaultChecked /> Agence immobilière</label>
          <label className="chip"><input type="radio" name="kind" value="promoteur" /> Promoteur</label>
        </div>
        <div className="field"><label htmlFor="name">Nom commercial</label><input id="name" name="name" className="inp" required /></div>
        <div className="field"><label htmlFor="commune">Commune du siège</label>
          <select id="commune" name="commune" className="inp">{communes.map((c) => <option key={c.slug} value={c.slug}>{tr(c.label, locale)}</option>)}</select></div>
        <button className="btn btn-p">Créer le compte et envoyer en vérification</button>
      </form>
    </div>
  );
}
