import Link from 'next/link';
import { PageHead } from '@/components/Notice';
import { createClient } from '@/lib/supabase/server';
import { requireStaff } from '@/lib/staff';

export default async function Page() {
  await requireStaff();
  const supabase = await createClient();
  const now = new Date().toISOString();
  const c = (q: PromiseLike<{ count: number | null }>) => q.then((r) => r.count ?? 0);
  const [queue, late, calls, moder, pay] = await Promise.all([
    c(supabase.from('verification_case').select('id', { count: 'exact', head: true }).is('closed_at', null)),
    c(supabase.from('verification_case').select('id', { count: 'exact', head: true }).is('closed_at', null).lt('due_at', now)),
    c(supabase.from('confirmation_call').select('id', { count: 'exact', head: true }).is('done_at', null).lte('due_at', now)),
    c(supabase.from('message').select('id', { count: 'exact', head: true }).eq('moderation_status', 'en_moderation')),
    c(supabase.from('payment').select('id', { count: 'exact', head: true }).eq('status', 'en_attente')),
  ]);
  const tiles = [
    ['Dossiers de vérification ouverts', queue, '/admin/verification'],
    ['En retard sur les 48 h ouvrées', late, '/admin/verification'],
    ['Appels à passer', calls, '/admin/appels'],
    ['Messages à modérer', moder, '/admin/moderation'],
    ['Virements à valider', pay, '/admin/paiements'],
  ] as const;
  return (
    <>
      <PageHead title="Vue d'ensemble" />
      <div className="grid g4">{tiles.map(([t, n, href]) => (
        <Link key={t} href={href} className="card pad stack" style={{ textDecoration: 'none', gap: 4 }}>
          <span className="small muted">{t}</span><span className="h-l num">{n}</span>
        </Link>))}</div>
    </>
  );
}
