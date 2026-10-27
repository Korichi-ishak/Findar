'use client';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';

// Connexion sans mot de passe : code à usage unique par SMS ou par e-mail.
// Le SMS demande un fournisseur configuré dans Supabase Auth (à choisir).
export function OtpForm({ next, configured }: { next: string; configured: boolean }) {
  const router = useRouter();
  const [step, setStep] = useState<'id' | 'code'>('id');
  const [ident, setIdent] = useState('');
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const isEmail = ident.includes('@');
  const phone = () => {
    const d = ident.replace(/[^\d+]/g, '');
    return d.startsWith('+') ? d : d.startsWith('0') ? `+213${d.slice(1)}` : `+213${d}`;
  };

  async function send(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true); setError(null);
    const supabase = createClient();
    const { error } = isEmail
      ? await supabase.auth.signInWithOtp({ email: ident.trim(), options: { shouldCreateUser: true } })
      : await supabase.auth.signInWithOtp({ phone: phone(), options: { shouldCreateUser: true } });
    setBusy(false);
    if (error) setError(error.message); else setStep('code');
  }

  async function verify(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true); setError(null);
    const supabase = createClient();
    const { error } = isEmail
      ? await supabase.auth.verifyOtp({ email: ident.trim(), token: code.trim(), type: 'email' })
      : await supabase.auth.verifyOtp({ phone: phone(), token: code.trim(), type: 'sms' });
    setBusy(false);
    if (error) return setError(error.message);
    router.replace(next);
    router.refresh();
  }

  if (step === 'id')
    return (
      <form onSubmit={send} className="stack">
        <div className="field">
          <label htmlFor="ident">Téléphone ou e-mail</label>
          <input id="ident" className="inp" required value={ident} onChange={(e) => setIdent(e.target.value)}
            placeholder="0555 12 34 56 ou nom@exemple.dz" autoComplete="username" />
          <span className="hint">On vous envoie un code. Pas de mot de passe.</span>
        </div>
        {error && <p className="notice warn small">{error}</p>}
        <button className="btn btn-p" disabled={busy || !configured}>{busy ? 'Envoi…' : 'Recevoir le code'}</button>
      </form>
    );

  return (
    <form onSubmit={verify} className="stack">
      <div className="field">
        <label htmlFor="code">Code reçu {isEmail ? 'par e-mail' : 'par SMS'}</label>
        <input id="code" className="inp num" required inputMode="numeric" autoComplete="one-time-code" maxLength={8}
          value={code} onChange={(e) => setCode(e.target.value)} />
      </div>
      {error && <p className="notice warn small">{error}</p>}
      <button className="btn btn-p" disabled={busy}>{busy ? 'Vérification…' : 'Se connecter'}</button>
      <button type="button" className="btn btn-g" onClick={() => setStep('id')}>Changer de numéro ou d&apos;e-mail</button>
    </form>
  );
}
