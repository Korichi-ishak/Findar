import { PageHead } from '@/components/Notice';
import { createClient } from '@/lib/supabase/server';
import { getViewer, proOrg } from '@/lib/session';
import { dateFr } from '@/lib/format';

export default async function Page() {
  const org = proOrg((await getViewer())!);
  const supabase = await createClient();
  const { data } = await supabase.from('organization_member').select('user_id, role_code, joined_at')
    .eq('organization_id', org?.organization_id ?? '').is('removed_at', null);
  const ids = (data ?? []).map((m) => m.user_id);
  const { data: people } = ids.length ? await supabase.from('profile').select('id, full_name, email').in('id', ids) : { data: [] };
  const name = Object.fromEntries((people ?? []).map((p) => [p.id, p.full_name || p.email]));
  return (
    <>
      <PageHead title="Équipe"><span className="todo">Invitation par lien : à construire</span></PageHead>
      <table className="tbl card"><thead><tr><th>Membre</th><th>Rôle</th><th>Depuis</th></tr></thead>
        <tbody>{(data ?? []).map((m) => <tr key={m.user_id}><td>{name[m.user_id] ?? '—'}</td><td>{m.role_code}</td><td className="small">{dateFr(m.joined_at)}</td></tr>)}</tbody></table>
    </>
  );
}
