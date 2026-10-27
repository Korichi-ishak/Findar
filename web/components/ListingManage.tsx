import { notFound } from 'next/navigation';
import { confirmStillAvailable, submitListing } from '@/app/actions/listing';
import { StatusBadge } from '@/components/StatusBadge';
import { dateFr, priceMain } from '@/lib/format';
import { createClient } from '@/lib/supabase/server';

const CASE: Record<string, string> = {
  documents: 'Pièces en cours d\'examen', a_corriger: 'À corriger', bien_a_verifier: 'Contrôle du bien à planifier',
  bien_planifie: 'Contrôle du bien planifié', valide: 'Validée', refuse: 'Refusée', annule: 'Annulée',
};

export async function ListingManage({ id, back }: { id: string; back: string }) {
  const supabase = await createClient();
  const { data: l } = await supabase.from('listing').select('*').eq('id', id).maybeSingle();
  if (!l) notFound();
  const [{ data: vcase }, { data: events }] = await Promise.all([
    supabase.from('verification_case').select('*').eq('listing_id', id).order('created_at', { ascending: false }).limit(1).maybeSingle(),
    supabase.from('listing_event').select('*').eq('listing_id', id).order('created_at', { ascending: false }).limit(20),
  ]);
  return (
    <div className="stack" style={{ gap: 20 }}>
      <div className="page-h">
        <div className="stack" style={{ gap: 4 }}><span className="eyebrow">Annonce {l.ref_code}</span><h1 className="h-l">{l.title?.fr || 'Sans titre'}</h1></div>
        <StatusBadge code={l.status_code} />
      </div>
      {l.metadata?.inactivity_asked_at && (
        <form action={confirmStillAvailable} className="notice warn row between">
          <span>Pas d&apos;activité depuis 30 jours. Le bien est-il toujours disponible ? Sans réponse sous 7 jours, l&apos;annonce sera masquée.</span>
          <input type="hidden" name="listing_id" value={id} /><input type="hidden" name="back" value={back} />
          <button className="btn btn-d btn-s">Oui, toujours disponible</button>
        </form>
      )}
      <dl className="kv card pad">
        <div><dt>Prix</dt><dd>{priceMain(l)}</dd></div>
        <div><dt>Vérification</dt><dd>{vcase ? CASE[vcase.status] : 'Pas encore envoyée'}</dd></div>
        <div><dt>Échéance promise</dt><dd>{dateFr(vcase?.due_at)}</dd></div>
        <div><dt>Badge</dt><dd>{l.verified_at ? `Vérifiée (${l.verified_method_code})` : '—'}</dd></div>
      </dl>
      {vcase?.decision_reason && <p className="notice warn">Motif de l&apos;agent : {vcase.decision_reason}</p>}
      {['brouillon', 'a_corriger'].includes(l.status_code) && (
        <form action={submitListing} className="row">
          <input type="hidden" name="listing_id" value={id} /><input type="hidden" name="back" value={back} />
          <button className="btn btn-p">Envoyer en vérification</button>
        </form>
      )}
      <section className="card pad stack">
        <h2 className="h-s">Historique</h2>
        <ul className="small stack" style={{ gap: 4, margin: 0, paddingInlineStart: 18 }}>
          {(events ?? []).map((e) => <li key={e.id}>{dateFr(e.created_at)} · {e.event_type} {e.payload?.to ? `→ ${e.payload.to}` : ''}</li>)}
        </ul>
      </section>
    </div>
  );
}
