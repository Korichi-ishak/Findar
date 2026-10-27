export function Pin({ size = 32 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 64 64" aria-hidden="true">
      <path d="M32 4C20.4 4 11 13.4 11 25c0 15.6 21 35 21 35s21-19.4 21-35C53 13.4 43.6 4 32 4z" fill="#FF5A1F" />
      <path d="M21 28.5 32 19l11 9.5V39H21z" fill="#fff" />
      <rect x="29" y="31" width="6" height="8" rx="1" fill="#101632" />
    </svg>
  );
}

export function Logo({ light = false }: { light?: boolean }) {
  return (
    <span className="logo">
      <Pin />
      <span className="logo-word" style={{ color: light ? 'var(--porc)' : 'var(--navy)' }}>
        fin<b>dar</b>
      </span>
    </span>
  );
}
