import type { ReactNode } from "react";
import { cn } from "../../lib/cn";
import { Icon, type IconName } from "./icons";

// Design component 1, Chip & badge: height 24, 12/500. Filled dot = on/active, hollow = not yet.
const TONES = {
  neutral: "bg-muted text-ink",
  sheet: "bg-sheet text-ink",
  danger: "bg-danger-soft text-danger-ink",
  pink: "bg-pink text-on-pink",
} as const;

export function Chip({ tone = "neutral", dot, icon, children, className }: { tone?: keyof typeof TONES; dot?: "filled" | "hollow"; icon?: IconName; children: ReactNode; className?: string }) {
  return (
    <span className={cn("inline-flex h-6 items-center gap-1.5 rounded-full text-chip font-medium whitespace-nowrap", dot || icon ? "pr-2.5 pl-2" : "px-2.5", TONES[tone], className)}>
      {dot && <span aria-hidden="true" className={cn("size-1.5 rounded-full", dot === "filled" ? "bg-current" : "border border-current")} />}
      {icon && <Icon name={icon} size={14} strokeWidth={2.2} />}
      {children}
    </span>
  );
}
