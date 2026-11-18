import type { CSSProperties } from "react";
import { cn } from "../../lib/cn";

/**
 * Sand block (boards 12/13): muted on cards, track on muted rows. Pulses slowly (1.5s); the
 * motion stops under prefers-reduced-motion. Size and radius come from `className`.
 */
export function Skeleton({
  className,
  tone = "muted",
  style,
}: {
  className?: string;
  tone?: "muted" | "track";
  style?: CSSProperties;
}) {
  return (
    <span
      aria-hidden="true"
      style={style}
      className={cn(
        "block animate-pulse-soft rounded-full",
        tone === "muted" ? "bg-muted" : "bg-track",
        className,
      )}
    />
  );
}
