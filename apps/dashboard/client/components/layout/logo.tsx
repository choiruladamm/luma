/** Luma mark (board header): yellow stabilo U with a pink dot. */
export function LogoMark({ size = 28 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 100 100" fill="none" aria-hidden="true" className="block flex-none">
      <path d="M26 34 C26 72, 74 72, 74 34" transform="translate(4 4)" stroke="#1A1A1A" strokeWidth="28" strokeLinecap="square" />
      <path d="M26 34 C26 72, 74 72, 74 34" stroke="#1A1A1A" strokeWidth="28" strokeLinecap="square" />
      <path d="M26 34 C26 72, 74 72, 74 34" stroke="#FFD84D" strokeWidth="20" strokeLinecap="square" />
      <circle cx="50" cy="22" r="9" fill="#FFC2D3" stroke="#1A1A1A" strokeWidth="4" />
    </svg>
  );
}

export function Wordmark() {
  return (
    <span className="flex items-center gap-2">
      <LogoMark />
      <span className="font-display text-lg font-semibold tracking-[-0.02em]">Luma</span>
      <span className="hidden text-[15px] font-medium text-ink2 min-[380px]:inline">admin</span>
    </span>
  );
}
