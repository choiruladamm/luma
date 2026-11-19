import type { KeyboardEvent } from "react";

/**
 * Arrow, Home, and End keys across the sibling buttons of a tablist or radiogroup: selects the
 * next one and moves focus to it. Pair with `tabIndex={selected ? 0 : -1}` so Tab enters the
 * group once, at the selected button.
 */
export function rovingKeyDown(
  e: KeyboardEvent<HTMLElement>,
  index: number,
  count: number,
  select: (index: number) => void,
) {
  const next = {
    ArrowRight: (index + 1) % count,
    ArrowDown: (index + 1) % count,
    ArrowLeft: (index - 1 + count) % count,
    ArrowUp: (index - 1 + count) % count,
    Home: 0,
    End: count - 1,
  }[e.key];
  if (next === undefined) return;
  e.preventDefault();
  select(next);
  e.currentTarget.parentElement?.querySelectorAll<HTMLElement>(":scope > button")[next]?.focus();
}
