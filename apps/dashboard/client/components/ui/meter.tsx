/** Thin progress bar (Detail user): track 8px, ink fill. */
export function ProgressBar({ value, label }: { value: number; label: string }) {
  const pct = Math.max(0, Math.min(100, value));
  return (
    <div role="progressbar" aria-label={label} aria-valuenow={Math.round(pct)} aria-valuemin={0} aria-valuemax={100} className="h-2 overflow-hidden rounded-full bg-track">
      <div className="h-full rounded-full bg-ink" style={{ width: `${pct}%` }} />
    </div>
  );
}

/**
 * Half-circle gauge (design component 2): track arc, ink part, pink part. `parts` are fractions
 * of the whole arc, drawn in order.
 */
export function Gauge({ parts, label, children }: { parts: { value: number; color: string }[]; label: string; children?: React.ReactNode }) {
  const r = 80;
  const length = Math.PI * r;
  let offset = 0;
  return (
    <div className="relative mx-auto h-[112px] w-[200px]">
      <svg viewBox="0 0 200 112" className="absolute inset-0" role="img" aria-label={label}>
        <path d="M20 100 A80 80 0 0 1 180 100" fill="none" stroke="var(--c-track)" strokeWidth="18" strokeLinecap="round" />
        {parts.map((p, i) => {
          const dash = Math.max(0, Math.min(1, p.value)) * length;
          const el = (
            <path key={i} d="M20 100 A80 80 0 0 1 180 100" fill="none" stroke={p.color} strokeWidth="18" strokeLinecap="round" strokeDasharray={`${dash} ${length}`} strokeDashoffset={-offset} />
          );
          offset += dash;
          return dash > 0 ? el : null;
        })}
      </svg>
      <div className="absolute inset-x-0 bottom-0 flex flex-col items-center">{children}</div>
    </div>
  );
}
