import { notFound } from 'next/navigation';
import { approveCase, decideDocument, logAttempt, requestChanges } from '@/app/actions/admin';
import { PageHead } from '@/components/Notice';
import { StatusBadge } from '@/components/StatusBadge';
import { dateFr, priceMain } from '@/lib/format';
import { createClient } from '@/lib/supabase/server';
import { requireStaff } from '@/lib/staff';

// Checklist de l'appel vidéo pièce par pièce. Elle vit dans checklist (jsonb) :
// ajouter un point ici ne demande aucune migration.
const CHECKLIST = ['identite_correspond', 'facade_et_entree', 'sejour', 'cuisine', 'chambres', 'salle_de_bain', 'vue_et_orientation', 'compteurs', 'surface_coherente', 'etage_coherent'];

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  await requireStaff(['verificateur', 'photographe']);
  const { id } = await params;
  const supabase = await createClient();
  const { data: c } = await supabase.from('verification_case').select('*').eq('id', id).maybeSingle();
  if (!c) notFound();
  const [docs, attempts, listing, outcomes, docTypes] = await Promise.all([
    supabase.from('verification_document').select('*').eq('case_id', id).order('uploaded_at'),
    supabase.from('verification_attempt').select('*').eq('case_id', id).order('created_at', { ascending: false }),
    c.listing_id ? supabase.from('listing').select('ref_code, title, price_dzd, category_code, rooms, surface_m2, floor').eq('id', c.listing_id).single() : Promise.resolve({ data: null }),
    supabase.from('ref_verification_outcome').select('code, label').eq('active', true).order('sort'),
    supabase.from('ref_document_type').select('code, label'),
  ]);
  const docLabel = Object.fromEntries((docTypes.data ?? []).map((d) => [d.code, d.label.fr as string]));
  const l = listing.data;

  return (
    <div className="stack" style={{ gap: 20 }}>
      <PageHead title={l ? `Annonce ${l.ref_code}` : `Dossier ${c.subject_type}`}><StatusBadge code={c.status} /></PageHead>
      {l && <dl className="kv card pad">
        <div><dt>Annonce</dt><dd>{l.title?.fr || '—'}</dd></div><div><dt>Prix</dt><dd>{priceMain(l)}</dd></div>
        <div><dt>Pièces</dt><dd>{l.rooms ?? '—'}</dd></div><div><dt>Surface</dt><dd>{l.surface_m2 ?? '—'} m²</dd></div>
        <div><dt>Étage</dt><dd>{l.floor ?? '—'}</dd></div><div><dt>Échéance</dt><dd>{dateFr(c.due_at)}</dd></div>
      </dl>}

      <section className="card pad stack">
        <h2 className="h-s">Pièces</h2>
        {(docs.data ?? []).map((d) => (
          <div key={d.id} className="row between" style={{ borderBottom: '1px solid var(--line-2)', paddingBottom: 10 }}>
            <span><strong>{docLabel[d.document_type_code] ?? d.document_type_code}</strong> <span className="small muted">déposée le {dateFr(d.uploaded_at)}</span></span>
            {d.decision ? <span className="small"><StatusBadge code={d.decision === 'conforme' ? 'valide' : d.decision} label={d.decision} /> · fichier effacé le {dateFr(d.purged_at)}</span> : (
              <form action={decideDocument} className="row">
                <input type="hidden" name="doc_id" value={d.id} /><input type="hidden" name="case_id" value={id} />
                <input name="note" className="inp" placeholder="Note (si à corriger)" style={{ width: 200 }} />
                <button className="btn btn-d btn-s" name="decision" value="conforme">Conforme</button>
                <button className="btn btn-o btn-s" name="decision" value="a_corriger">À corriger</button>
                <button className="btn btn-o btn-s" name="decision" value="refuse">Refuser</button>
              </form>)}
          </div>))}
        {!docs.data?.length && <p className="small muted">Aucune pièce déposée.</p>}
      </section>

      <section className="card pad stack">
        <h2 className="h-s">Contrôle du bien (visio Zoom ou tournage 360°)</h2>
        <form action={logAttempt} className="stack">
          <input type="hidden" name="case_id" value={id} />
          <div className="row">
            <select name="method" className="inp" style={{ width: 'auto' }} defaultValue={c.method_code ?? 'visio'}>
              <option value="visio">Appel vidéo</option><option value="visite_360">Visite 360°</option>
            </select>
            <select name="outcome" className="inp" style={{ width: 'auto' }}>
              {(outcomes.data ?? []).map((o) => <option key={o.code} value={o.code}>{o.label.fr}</option>)}
            </select>
          </div>
          <div className="row" style={{ gap: 8 }}>{CHECKLIST.map((k) => <label key={k} className="chip"><input type="checkbox" name={`chk_${k}`} /> {k.replaceAll('_', ' ')}</label>)}</div>
          <textarea name="report" className="inp" rows={3} placeholder="Compte rendu (pas d'enregistrement de l'appel)" />
          <button className="btn btn-o btn-s" style={{ width: 'fit-content' }}>Enregistrer le contrôle</button>
        </form>
        <ul className="small stack" style={{ gap: 4, margin: 0, paddingInlineStart: 18 }}>
          {(attempts.data ?? []).map((a) => <li key={a.id}>{dateFr(a.created_at)} · {a.method_code} · {a.outcome_code} · {a.report}</li>)}
        </ul>
      </section>

      {c.subject_type === 'listing' && !c.closed_at && (
        <section className="card pad row between">
          <form action={approveCase} className="row">
            <input type="hidden" name="case_id" value={id} />
            <select name="method" className="inp" style={{ width: 'auto' }} defaultValue={c.method_code ?? 'visio'}>
              <option value="visio">Badge : vérifié en visio</option><option value="visite_360">Badge : vérifié 360°</option>
            </select>
            <button className="btn btn-p">Valider et publier</button>
          </form>
          <form action={requestChanges} className="row">
            <input type="hidden" name="case_id" value={id} />
            <input name="reason" className="inp" required placeholder="Motif (obligatoire)" style={{ width: 240 }} />
            <button className="btn btn-o" name="final" value="0">Demander une correction</button>
            <button className="btn btn-o" name="final" value="1">Refuser</button>
          </form>
        </section>)}
    </div>
  );
}
