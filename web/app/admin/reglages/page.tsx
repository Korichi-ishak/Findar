import { saveSetting } from '@/app/actions/admin';
import { PageHead } from '@/components/Notice';
import { dateFr } from '@/lib/format';
import { createClient } from '@/lib/supabase/server';
import { requireStaff } from '@/lib/staff';

export default async function Page() {
  await requireStaff(['super_admin']);
  const supabase = await createClient();
  const { data } = await supabase.from('app_setting').select('*').order('key');
  return (
    <>
      <PageHead title="Réglages" />
      <p className="notice small">Chaque délai, seuil ou limite de la plateforme se change ici, sans redéployer ni toucher à la base. Chaque modification est inscrite au journal d&apos;audit.</p>
      <div className="stack">{(data ?? []).map((s) => (
        <form key={s.key} action={saveSetting} className="card pad row between">
          <input type="hidden" name="key" value={s.key} />
          <div className="stack" style={{ gap: 2, flex: 1, minWidth: 240 }}>
            <code className="small">{s.key}</code>
            <span className="small muted">{s.description}</span>
            <span className="tiny muted">Modifié le {dateFr(s.updated_at)}{s.is_public ? ' · visible côté site' : ''}</span>
          </div>
          <div className="row">
            <input name="value" className="inp num" defaultValue={JSON.stringify(s.value)} style={{ width: 320 }} aria-label={s.key} />
            <button className="btn btn-d btn-s">Enregistrer</button>
          </div>
        </form>))}</div>
    </>
  );
}
