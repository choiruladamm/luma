import { type KeyboardEvent, useEffect, useId, useRef, useState } from "react";
import { cn } from "../../lib/cn";
import { Icon } from "./icons";

export type SelectOption<T extends string> = [value: T, text: string];

/**
 * Stabilo select (design component 1, menu style): a pill trigger showing `label` + the chosen text, and a
 * listbox popover (radius 24, sheet shadow, track ring) with a check on the chosen option.
 * Keyboard: ↑/↓ open and move, Home/End, Enter/Space choose, Esc closes back to the trigger.
 * `active` paints the trigger ink (a filter that differs from its default). The menu opens below,
 * or above when the viewport has no room below (bottom sheets, footers); `up` forces above.
 * `block` fills the row (phone sheets). `shortLabel` replaces the label below 768px ("" hides it).
 */
export function Select<T extends string>({
  label,
  shortLabel,
  value,
  options,
  onChange,
  active,
  block,
  up,
  hideLabel,
  className,
}: {
  label: string;
  shortLabel?: string;
  value: T;
  options: SelectOption<T>[];
  onChange: (value: T) => void;
  active?: boolean;
  block?: boolean;
  up?: boolean;
  hideLabel?: boolean;
  className?: string;
}) {
  const [open, setOpen] = useState(false);
  const [focus, setFocus] = useState(0);
  const [above, setAbove] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const items = useRef<(HTMLLIElement | null)[]>([]);
  const listId = useId();
  const selected = Math.max(
    0,
    options.findIndex(([v]) => v === value),
  );
  const text = options[selected]?.[1] ?? "";

  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => !root.current?.contains(e.target as Node) && setOpen(false);
    document.addEventListener("mousedown", onDown);
    return () => document.removeEventListener("mousedown", onDown);
  }, [open]);

  useEffect(() => {
    if (open) items.current[focus]?.focus();
  }, [open, focus]);

  const show = (at = selected) => {
    const box = trigger.current?.getBoundingClientRect();
    const height = options.length * 42 + 16; // rows of 40 + gaps + padding
    setAbove(
      up || (!!box && window.innerHeight - box.bottom < height + 12 && box.top > height + 12),
    );
    setFocus(at);
    setOpen(true);
  };
  const close = (refocus = true) => {
    setOpen(false);
    if (refocus) trigger.current?.focus();
  };
  const choose = (i: number) => {
    onChange(options[i]![0]);
    close();
  };

  const onTriggerKey = (e: KeyboardEvent) => {
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      show();
    }
  };
  const onListKey = (e: KeyboardEvent) => {
    const last = options.length - 1;
    const moves: Record<string, number> = {
      ArrowDown: Math.min(last, focus + 1),
      ArrowUp: Math.max(0, focus - 1),
      Home: 0,
      End: last,
    };
    if (e.key in moves) {
      e.preventDefault();
      setFocus(moves[e.key]!);
    } else if (e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      choose(focus);
    } else if (e.key === "Escape") {
      e.preventDefault();
      close();
    } else if (e.key === "Tab") close(false);
  };

  return (
    <div ref={root} className={cn("relative", block ? "w-full" : "inline-flex", className)}>
      <button
        ref={trigger}
        type="button"
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={open ? listId : undefined}
        aria-label={`${label}: ${text}`}
        onClick={() => (open ? close() : show())}
        onKeyDown={onTriggerKey}
        className={cn(
          "inline-flex h-10 max-w-full min-w-0 items-center gap-1.5 rounded-full pr-3 pl-3.5 text-caption font-medium whitespace-nowrap transition-colors",
          active ? "bg-ink text-canvas" : "bg-muted text-ink hover:bg-track",
          block && "h-12 w-full justify-between pr-4 text-body",
        )}
      >
        {!hideLabel && (
          <span className={cn("flex-none", active ? "text-canvas/70" : "text-ink2")}>
            {shortLabel === undefined ? (
              label
            ) : (
              <>
                <span className="max-md:hidden">{label}</span>
                {shortLabel && <span className="md:hidden">{shortLabel}</span>}
              </>
            )}
          </span>
        )}
        <span className={cn("flex min-w-0 items-center gap-1.5", block && "ml-auto")}>
          <span className="truncate">{text}</span>
          <Icon
            name="chevdown"
            size={14}
            className={cn("transition-transform duration-150", open && "rotate-180")}
          />
        </span>
      </button>
      {open && (
        <ul
          id={listId}
          role="listbox"
          aria-label={label}
          onKeyDown={onListKey}
          className={cn(
            "absolute z-40 m-0 flex min-w-full list-none flex-col gap-0.5 rounded-menu bg-sheet p-1.5 shadow-[var(--shadow-sheet),inset_0_0_0_1px_var(--c-track)]",
            above ? "bottom-[calc(100%+6px)]" : "top-[calc(100%+6px)]",
            block ? "inset-x-0" : "left-0 w-max",
          )}
        >
          {options.map(([v, label], i) => (
            <li
              key={v}
              ref={(el) => {
                items.current[i] = el;
              }}
              role="option"
              tabIndex={-1}
              aria-selected={i === selected}
              onClick={() => choose(i)}
              onMouseEnter={() => setFocus(i)}
              className={cn(
                "flex h-10 cursor-pointer items-center justify-between gap-4 rounded-[16px] px-3 text-body whitespace-nowrap outline-none",
                i === focus && "bg-muted",
                i === selected ? "font-semibold" : "font-normal",
              )}
            >
              {label}
              <Icon name="check" size={16} className={i === selected ? "" : "invisible"} />
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
