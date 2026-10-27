'use server';
import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';

// Les droits sont vérifiés par la base (RLS + fonctions). Ces actions ne font que relayer.
const fail = (e: { message: string } | null) => { if (e) throw new Error(e.message); };

export async function decideDocument(fd: FormData) {
  const supabase = await createClient();
  // La base efface le fichier et ne garde que la décision (trigger purge_document_on_decision).
  const { error } = await supabase.from('verification_document')
    .update({ decision: String(fd.get('decision')), decision_note: String(fd.get('note') ?? '') || null })
    .eq('id', String(fd.get('doc_id')));
  fail(error); revalidatePath(`/admin/verification/${fd.get('case_id')}`);
}

export async function logAttempt(fd: FormData) {
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  const checklist = Object.fromEntries([...fd.keys()].filter((k) => k.startsWith('chk_')).map((k) => [k.slice(4), true]));
  const { error } = await supabase.from('verification_attempt').insert({
    case_id: String(fd.get('case_id')), method_code: String(fd.get('method')), agent_id: claims?.claims?.sub,
    started_at: new Date().toISOString(), ended_at: new Date().toISOString(),
    outcome_code: String(fd.get('outcome')), report: String(fd.get('report') ?? ''), checklist,
  });
  fail(error); revalidatePath(`/admin/verification/${fd.get('case_id')}`);
}

export async function approveCase(fd: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('approve_listing_verification', { p_case: String(fd.get('case_id')), p_method: String(fd.get('method')) });
  fail(error); revalidatePath('/admin/verification'); redirect('/admin/verification');
}

export async function requestChanges(fd: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('request_listing_changes', {
    p_case: String(fd.get('case_id')), p_reason: String(fd.get('reason') ?? ''), p_final: fd.get('final') === '1',
  });
  fail(error); revalidatePath('/admin/verification'); redirect('/admin/verification');
}

export async function closeCall(fd: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.from('confirmation_call')
    .update({ outcome: String(fd.get('outcome')), outcome_note: String(fd.get('note') ?? '') || null, done_at: new Date().toISOString() })
    .eq('id', String(fd.get('call_id')));
  fail(error); revalidatePath('/admin/appels');
}

export async function moderateMessage(fd: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.from('message').update({ moderation_status: String(fd.get('status')) }).eq('id', String(fd.get('message_id')));
  fail(error); revalidatePath('/admin/moderation');
}

export async function setOrgStatus(fd: FormData) {
  const supabase = await createClient();
  const status = String(fd.get('status'));
  const { error } = await supabase.from('organization')
    .update({ verification_status: status, verified_at: status === 'verifiee' ? new Date().toISOString() : null })
    .eq('id', String(fd.get('org_id')));
  fail(error); revalidatePath('/admin/comptes');
}

export async function setPaymentStatus(fd: FormData) {
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  const status = String(fd.get('status'));
  const { error } = await supabase.from('payment')
    .update({ status, validated_by: claims?.claims?.sub, paid_at: status === 'paye' ? new Date().toISOString() : null })
    .eq('id', String(fd.get('payment_id')));
  fail(error); revalidatePath('/admin/paiements');
}

/** Réglage : la valeur est du JSON (nombre, texte entre guillemets, liste, objet). */
export async function saveSetting(fd: FormData) {
  const raw = String(fd.get('value'));
  let value: unknown;
  try { value = JSON.parse(raw); } catch { throw new Error(`Valeur JSON invalide : ${raw}`); }
  const supabase = await createClient();
  const { error } = await supabase.from('app_setting').update({ value }).eq('key', String(fd.get('key')));
  fail(error); revalidatePath('/admin/reglages');
}

const REF_TABLES = new Set(['ref_category', 'ref_property_type', 'ref_listing_status', 'ref_org_kind', 'ref_member_role', 'ref_staff_role',
  'ref_document_type', 'ref_verification_method', 'ref_verification_outcome', 'ref_dossier_step', 'ref_poi_kind', 'ref_report_reason',
  'ref_questionnaire_answer']);

/** Ajoute ou modifie une valeur de liste. On ne supprime jamais : on désactive. */
export async function saveRef(fd: FormData) {
  const table = String(fd.get('table'));
  if (!REF_TABLES.has(table)) throw new Error('Table inconnue');
  let meta: unknown;
  try { meta = JSON.parse(String(fd.get('meta') || '{}')); } catch { throw new Error('meta : JSON invalide'); }
  const label: Record<string, string> = { fr: String(fd.get('fr')) };
  for (const l of ['ar', 'en']) if (fd.get(l)) label[l] = String(fd.get(l));
  const supabase = await createClient();
  const { error } = await supabase.from(table).upsert({
    code: String(fd.get('code')).trim(), label, sort: Number(fd.get('sort') ?? 0), active: fd.get('active') === 'on', meta,
  });
  fail(error); revalidatePath('/admin/referentiels');
}
