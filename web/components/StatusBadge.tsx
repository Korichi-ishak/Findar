const TONE: Record<string, string> = {
  brouillon: 'b-sand', en_verification: 'b-info', verification_bien: 'b-info', a_corriger: 'b-warn',
  disponible: 'b-good', reservee: 'b-orange', compromis_signe: 'b-navy', vendue_findar: 'b-navy',
  vendue_ailleurs: 'b-sand', retiree: 'b-sand', suspendue: 'b-bad',
  documents: 'b-info', bien_a_verifier: 'b-info', bien_planifie: 'b-info', valide: 'b-good', refuse: 'b-bad', annule: 'b-sand',
  proposee: 'b-warn', confirmee: 'b-good', faite: 'b-navy', non_venue: 'b-bad', annulee: 'b-sand', expiree: 'b-sand',
  en_attente: 'b-warn', paye: 'b-good', echoue: 'b-bad', en_moderation: 'b-warn', masque: 'b-bad', ok: 'b-good',
};

/** Le libellé vient de la base (ref_*) quand on l'a ; sinon le code, lisible. */
export function StatusBadge({ code, label }: { code: string; label?: string }) {
  return <span className={`badge ${TONE[code] ?? 'b-sand'}`}>{label ?? code.replaceAll('_', ' ')}</span>;
}
