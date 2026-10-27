import { notFound } from 'next/navigation';
import { confirmVisit, proposeVisit, sendMessage } from '@/app/actions/dossier';
import { StatusBadge } from '@/components/StatusBadge';
import { dateFr } from '@/lib/format';
import { createClient } from '@/lib/supabase/server';
import type { Viewer } from '@/lib/session';

const STEP: Record<string, string> = {
  contact: 'Demande de contact', visite_demandee: 'Visite proposée', visite_confirmee: 'Visite confirmée', visite_faite: 'Visite faite',
  questionnaire: 'Questionnaire', offre: 'Offre', reservation: 'Réservation', compromis: 'Compromis', conclu: 'Conclu',
};
const SIDE: Record<string, string> = { buyer: 'Acheteur', seller: 'Annonceur', findar: 'Findar', system: 'Findar' };

/** Un dossier = une annonce + un acheteur. Même écran des deux côtés ; chacun ne voit que ses boutons. */
export async function DossierView({ id, viewer }: { id: string; viewer: Viewer }) {
  const supabase = await createClient();
  const { data: d } = await supabase.from('dossier').select('*, listing:listing_id (ref_code, title)').eq('id', id).maybeSingle();
  if (!d) notFound();
  const [events, visits, messages] = await Promise.all([
    supabase.from('dossier_event').select('*').eq('dossier_id', id).order('id'),
    supabase.from('visit').select('*').eq('dossier_id', id).order('starts_at', { ascending: false }),
    supabase.from('message').select('*').eq('dossier_id', id).order('created_at'),
  ]);
  const me = d.buyer_id === viewer.id ? 'buyer' : 'seller';
  const listing = Array.isArray(d.listing) ? d.listing[0] : d.listing;

  return (
    <div className="stack" style={{ gap: 20 }}>
      <div className="page-h">
        <div className="stack" style={{ gap: 4 }}>
          <span className="eyebrow">Dossier · annonce {listing?.ref_code ?? ''}</span>
          <h1 className="h-l">{listing?.title?.fr ?? 'Annonce'}</h1>
        </div>
        <StatusBadge code={d.current_step_code} label={STEP[d.current_step_code]} />
      </div>

      <section className="card pad stack">
        <h2 className="h-s">Visites</h2>
        {(visits.data ?? []).map((v) => {
          const mine = me === 'buyer' ? v.buyer_confirmed_at : v.seller_confirmed_at;
          return (
            <div key={v.id} className="row between" style={{ borderBottom: '1px solid var(--line-2)', paddingBottom: 10 }}>
              <div className="stack" style={{ gap: 2 }}>
                <strong>{dateFr(v.starts_at)}</strong>
                <span className="small muted">
                  Acheteur {v.buyer_confirmed_at ? '✓' : '…'} · Annonceur {v.seller_confirmed_at ? '✓' : '…'}
                  {v.address_released_at && ` · adresse donnée le ${dateFr(v.address_released_at)}`}
                </span>
              </div>
              <div className="row">
                <StatusBadge code={v.status} />
                {v.status === 'proposee' && !mine && (
                  <form action={confirmVisit}>
                    <input type="hidden" name="dossier_id" value={id} />
                    <input type="hidden" name="visit_id" value={v.id} />
                    <input type="hidden" name="version" value={v.version} />
                    <button className="btn btn-p btn-s">Confirmer ce créneau</button>
                  </form>
                )}
              </div>
            </div>
          );
        })}
        <form action={proposeVisit} className="row">
          <input type="hidden" name="dossier_id" value={id} />
          <input type="datetime-local" name="starts_at" className="inp" required style={{ width: 'auto' }} aria-label="Créneau proposé" />
          <button className="btn btn-o btn-s">Proposer un créneau</button>
        </form>
      </section>

      <section className="card pad stack">
        <h2 className="h-s">Messages</h2>
        <p className="small muted">Pas de numéro, pas d&apos;argent avant la visite : ces messages partent en vérification.</p>
        <div className="stack" style={{ gap: 8 }}>
          {(messages.data ?? []).map((m) => (
            <div key={m.id} style={{ alignSelf: m.side === me ? 'flex-end' : 'flex-start', maxWidth: '80%' }}
              className={`card pad${m.side === me ? '' : ''}`}>
              <div className="tiny muted">{SIDE[m.side]} · {dateFr(m.created_at)} {m.moderation_status !== 'ok' && <StatusBadge code={m.moderation_status} label="en vérification" />}</div>
              <p>{m.body}</p>
            </div>
          ))}
        </div>
        <form action={sendMessage} className="row">
          <input type="hidden" name="dossier_id" value={id} />
          <input name="body" className="inp" style={{ flex: 1 }} maxLength={2000} required placeholder="Votre message" aria-label="Message" />
          <button className="btn btn-d btn-s">Envoyer</button>
        </form>
      </section>

      <section className="card pad stack">
        <h2 className="h-s">Historique</h2>
        <ol className="small stack" style={{ gap: 4, margin: 0, paddingInlineStart: 18 }}>
          {(events.data ?? []).map((e) => <li key={e.id}>{dateFr(e.created_at)} · {SIDE[e.side]} · {STEP[e.step_code] ?? e.step_code} ({e.kind})</li>)}
        </ol>
      </section>
    </div>
  );
}
