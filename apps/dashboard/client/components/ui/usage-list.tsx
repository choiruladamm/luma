import { Link } from "react-router";

export type UsageRow = {
  label: string;
  title?: string;
  href?: string;
  value: string;
  note: string;
};

/** Titled list of usage rows: label left, value with a caption right. Renders nothing when empty. */
export function UsageList({ title, rows }: { title: string; rows: UsageRow[] }) {
  if (rows.length === 0) return null;
  return (
    <div className="flex flex-col gap-2">
      <h3 className="m-0 text-body font-semibold text-ink2">{title}</h3>
      <ul className="m-0 flex list-none flex-col gap-2 p-0">
        {rows.map((r, i) => (
          <li key={i} className="flex min-h-12 items-center gap-3 rounded-row bg-muted px-4 py-2">
            {r.href ? (
              <Link
                to={r.href}
                title={r.title}
                className="min-w-0 flex-1 truncate text-body font-semibold text-ink no-underline hover:underline"
              >
                {r.label}
              </Link>
            ) : (
              <span className="min-w-0 flex-1 truncate text-body font-semibold" title={r.title}>
                {r.label}
              </span>
            )}
            <span className="flex flex-col items-end text-right">
              <span className="text-body tabular-nums">{r.value}</span>
              <span className="text-caption text-ink2 tabular-nums">{r.note}</span>
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}

/** Small number tile for usage cards: label, value, optional caption. */
export function MiniStat({ label, value, note }: { label: string; value: string; note?: string }) {
  return (
    <div className="flex min-w-0 flex-col gap-1 rounded-row bg-muted p-4">
      <span className="text-caption text-ink2">{label}</span>
      <span className="text-[22px] leading-none font-semibold tracking-[-0.02em] tabular-nums">
        {value}
      </span>
      {note && <span className="text-caption text-ink2">{note}</span>}
    </div>
  );
}
