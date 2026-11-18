import { cn } from "../../lib/cn";

const PALETTE = ["bg-[var(--c-av0)]", "bg-[var(--c-av1)]", "bg-[var(--c-av2)]", "bg-[var(--c-av3)]", "bg-[var(--c-av4)]", "bg-[var(--c-av5)]"];
const SIZES = { 36: "size-9 text-body", 40: "size-10 text-card", 72: "size-[72px] text-[28px]" } as const;

/** Same email → same color, every time (design component 2, Table). */
export function avatarColor(seed: string) {
  let hash = 0;
  for (const ch of seed) hash = (hash * 31 + ch.charCodeAt(0)) >>> 0;
  return PALETTE[hash % PALETTE.length]!;
}

export function Avatar({ seed, label, size = 36, className }: { seed: string; label: string; size?: keyof typeof SIZES; className?: string }) {
  return (
    <span aria-hidden="true" className={cn("flex flex-none items-center justify-center rounded-full font-semibold text-[#1a1a1a] uppercase", SIZES[size], avatarColor(seed), className)}>
      {label.trim().charAt(0) || "?"}
    </span>
  );
}
