import { cn } from "../../lib/cn";

/** Sand block that pulses slowly (1.5s); the motion stops under prefers-reduced-motion. */
export function Skeleton({ className }: { className?: string }) {
  return <span aria-hidden="true" className={cn("block animate-pulse-soft rounded-full bg-track", className)} />;
}
