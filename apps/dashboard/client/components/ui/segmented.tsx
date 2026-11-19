import type { ReactNode } from "react";
import { useSlidingPill } from "../../hooks/use-sliding-pill";
import { cn } from "../../lib/cn";
import { rovingKeyDown } from "../../lib/roving";

// `count` may be a skeleton while the list loads, so the tabs keep their width.
type Option<T extends string> = { value: T; label: ReactNode; count?: ReactNode };

// Design component 2, Segmented: muted track radius 26, pad 4; options 40 tall; active = sheet + soft shadow.
// `kind="tabs"` for filters (tablist), `"radio"` for settings (radiogroup). `stretch`: equal
// options across the full width; `"phone"` only below 768px.
export function Segmented<T extends string>({
  label,
  value,
  onChange,
  options,
  kind = "tabs",
  stretch,
  className,
}: {
  label: string;
  value: T;
  onChange: (v: T) => void;
  options: Option<T>[];
  kind?: "tabs" | "radio";
  stretch?: boolean | "phone";
  className?: string;
}) {
  const active = options.findIndex((o) => o.value === value);
  // Active = sheet + soft shadow, hover = faint canvas; both slide (useSlidingPill).
  const pill = useSlidingPill(active, options.length);
  return (
    <div
      role={kind === "tabs" ? "tablist" : "radiogroup"}
      aria-label={label}
      onMouseLeave={pill.onMouseLeave}
      className={cn(
        "relative rounded-[26px] bg-muted p-1",
        stretch === true
          ? "flex w-full gap-0.5"
          : stretch === "phone"
            ? "inline-flex gap-1 max-md:flex max-md:w-full max-md:gap-0.5"
            : "inline-flex gap-1",
        className,
      )}
    >
      <span
        aria-hidden="true"
        style={pill.hoverStyle}
        className={cn(
          "absolute top-1 left-0 h-10 rounded-[20px] bg-canvas/60",
          pill.slide,
          pill.hoverVisible ? "opacity-100" : "opacity-0",
        )}
      />
      <span
        aria-hidden="true"
        style={pill.activeStyle}
        className={cn(
          "absolute top-1 left-0 h-10 rounded-[20px] bg-segment shadow-segment",
          pill.slide,
          pill.activeVisible ? "opacity-100" : "opacity-0",
        )}
      />
      {options.map((o, i) => {
        const on = i === active;
        return (
          <button
            key={o.value}
            {...pill.item(i)}
            type="button"
            role={kind === "tabs" ? "tab" : "radio"}
            aria-selected={kind === "tabs" ? on : undefined}
            aria-checked={kind === "radio" ? on : undefined}
            // No selection yet (-1): the first option takes the tab stop.
            tabIndex={on || (active < 0 && i === 0) ? 0 : -1}
            onClick={() => onChange(o.value)}
            onKeyDown={(e) =>
              rovingKeyDown(e, i, options.length, (next) => onChange(options[next]!.value))
            }
            className={cn(
              "relative z-10 inline-flex h-10 items-center justify-center rounded-[20px] text-ink whitespace-nowrap",
              stretch === true
                ? ""
                : stretch === "phone"
                  ? "gap-2 px-4 max-md:min-w-0 max-md:flex-1 max-md:gap-1.5 max-md:px-1.5"
                  : "gap-2 px-4",
              kind === "radio" ? "text-caption" : "text-body",
              // Equal thirds that may shrink (the account menu is only 304 wide).
              stretch === true && "min-w-0 flex-1 gap-1.5 px-1.5",
              on ? "font-semibold" : "font-medium",
            )}
          >
            {o.label}
            {o.count !== undefined && (
              <span className="font-semibold text-ink2 tabular-nums">{o.count}</span>
            )}
          </button>
        );
      })}
    </div>
  );
}
