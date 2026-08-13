export function LysLogo({ className }: { className?: string }) {
  return (
    <svg
      aria-hidden="true"
      className={className ?? 'lys-logo'}
      fill="none"
      viewBox="0 0 32 32"
    >
      <circle cx="16" cy="16" r="3.25" fill="currentColor" />
      <path
        d="M16 2.5v7M16 22.5v7M2.5 16h7M22.5 16h7M6.45 6.45l4.95 4.95M20.6 20.6l4.95 4.95M25.55 6.45 20.6 11.4M11.4 20.6l-4.95 4.95"
        stroke="currentColor"
        strokeLinecap="round"
        strokeWidth="2"
      />
    </svg>
  );
}
