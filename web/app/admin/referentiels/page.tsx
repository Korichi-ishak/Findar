import Link from 'next/link';
import { saveRef } from '@/app/actions/admin';
import { PageHead } from '@/components/Notice';
import { createClient } from '@/lib/supabase/server';
import { requireStaff } from '@/lib/staff';
import type { RefRow } from '@/types/api';

const TABLES: [string, string][] = [
  ['ref_listing_status', 'Statuts d\'annonce'], ['ref_category', 'Catégories'], ['ref_property_type', 'Types de bien'],
  ['ref_dossier_step', 'Étapes du dossier'], ['ref_document_type', 'Pièces de vérification'], ['ref_verification_method', 'Méthodes de vérification'],
  ['ref_verification_outcome', 'Résultats de contrôle'], ['ref_questionnaire_answer', 'Réponses au questionnaire'], ['ref_poi_kind', 'Lieux à proximité'],
  ['ref_report_reason', 'Motifs de signalement'], ['ref_member_role', 'Rôles en agence'], ['ref_staff_role', 'Rôles Findar'], ['ref_org_kind', 'Types d\'organisation'],
];

function RefForm({ table, row }: { table: string; row?: RefRow }) {
  return (
    <form action={saveRef} className="card pad stack" style={{ gap: 10 }}>
      <input type="hidden" name="table" value={table} />
      <div className="filters">
        <div className="field"><label>Code</label><input name="code" className="inp" defaultValue={row?.code} readOnly={!!row} required pattern="[a-z0-9_]+" /></div>
        <div className="field"><label>Français</label><input name="fr" className="inp" defaultValue={row?.label.fr} required /></div>
        <div className="field"><label>Arabe</label><input name="ar" className="inp" dir="rtl" defaultValue={row?.label.ar} /></div>
        <div className="field"><label>Anglais</label><input name="en" className="inp" defaultValue={row?.label.en} /></div>
        <div className="field"><label>Ordre</label><input name="sort" className="inp num" defaultValue={row?.sort ?? 0} /></div>
      </div>
      <div className="field"><label>Paramètres (JSON)</label><input name="meta" className="inp" defaultValue={JSON.stringify(row?.meta ?? {})} /></div>
      <div className="row between">
        <label className="row"><input type="checkbox" name="active" defaultChecked={row?.active ?? true} /> Active (décocher au lieu de supprimer)</label>
        <button className="btn btn-d btn-s">{row ? 'Enregistrer' : 'Ajouter'}</button>
      </div>
    </form>
  );
}

export default async function Page({ searchParams }: { searchParams: Promise<{ t?: string }> }) {
  await requireStaff(['super_admin']);
  const { t } = await searchParams;
  const table = TABLES.find(([k]) => k === t)?.[0] ?? TABLES[0][0];
  const supabase = await createClient();
  const { data } = await supabase.from(table).select('*').order('sort');
  return (
    <>
      <PageHead title="Listes de valeurs" />
      <p className="notice small">Ajouter un statut, un type de bien ou un motif = une ligne ici. Le code ne change jamais une fois créé ; une valeur inutile se désactive.</p>
      <div className="row" style={{ gap: 6 }}>{TABLES.map(([k, label]) => (
        <Link key={k} href={`/admin/referentiels?t=${k}`} className="chip" aria-pressed={k === table} style={{ textDecoration: 'none' }}>{label}</Link>))}</div>
      <div className="stack">{((data ?? []) as RefRow[]).map((r) => <RefForm key={r.code} table={table} row={r} />)}</div>
      <h2 className="h-s">Nouvelle valeur</h2>
      <RefForm table={table} />
    </>
  );
}
