import type { ReactNode } from "react";
import { cn } from "../../lib/cn";

type Option<T extends string> = { value: T; label: ReactNode; count?: number };

// Komponen 2, Segmented: muted track radius 26, pad 4; options 40 tall; active = sheet + soft shadow.
// `kind="tabs"` for filters (tablist), `"radio"` for settings (radiogroup).
export function Segmented<T extends string>({ label, value, onChange, options, kind = "tabs", stretch, className }: { label: string; value: T; onChange: (v: T) => void; options: Option<T>[]; kind?: "tabs" | "radio"; stretch?: boolean; className?: string }) {
  return (
    <div role={kind === "tabs" ? "tablist" : "radiogroup"} aria-label={label} className={cn("inline-flex gap-1 rounded-[26px] bg-muted p-1", stretch && "flex w-full gap-0.5", className)}>
      {options.map((o) => {
        const active = o.value === value;
        return (
          <button
            key={o.value}
            type="button"
            role={kind === "tabs" ? "tab" : "radio"}
            aria-selected={kind === "tabs" ? active : undefined}
            aria-checked={kind === "radio" ? active : undefined}
            onClick={() => onChange(o.value)}
            className={cn(
              "inline-flex h-10 items-center justify-center gap-2 rounded-[20px] px-4 text-ink whitespace-nowrap",
              kind === "radio" ? "text-caption" : "text-body",
              stretch && "flex-1 px-2",
              active ? "bg-segment font-semibold shadow-segment" : "font-medium hover:bg-canvas/60",
            )}
          >
            {o.label}
            {o.count !== undefined && <span className="font-semibold text-ink2 tabular-nums">{o.count}</span>}
          </button>
        );
      })}
    </div>
  );
}
