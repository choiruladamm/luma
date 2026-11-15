import type { HTMLAttributes, ReactNode } from "react";
import { cn } from "../../lib/cn";
import { Icon, type IconName } from "./icons";

/** Komponen 2, Kartu: padding 24, radius 20, sheet, no border, flat (no shadow). */
export function Card({ className, ...props }: HTMLAttributes<HTMLElement>) {
  return <section className={cn("flex flex-col gap-3.5 rounded-card bg-sheet p-6", className)} {...props} />;
}

export function CardHeader({ id, title, subtitle, action }: { id?: string; title: ReactNode; subtitle?: ReactNode; action?: ReactNode }) {
  return (
    <div className={cn("flex flex-wrap items-center justify-between gap-3", action ? "min-h-11" : false)}>
      <div className="flex flex-col gap-0.5">
        <h2 id={id} className="m-0 text-card font-semibold tracking-[-0.01em]">
          {title}
        </h2>
        {subtitle && <span className="text-caption text-ink2">{subtitle}</span>}
      </div>
      {action}
    </div>
  );
}

/** Komponen 1, kartu angka: label left, icon tile right, 36/600 number, caption pinned to the bottom. */
export function StatCard({ label, icon, value, note, danger }: { label: string; icon: IconName; value: ReactNode; note?: ReactNode; danger?: boolean }) {
  return (
    <section aria-label={label} className="flex min-h-[140px] flex-col gap-3.5 rounded-card bg-sheet px-[22px] py-5">
      <div className="flex items-center justify-between gap-2">
        <span className="text-body font-medium text-ink2">{label}</span>
        <span className="flex size-8 items-center justify-center rounded-tile bg-muted text-ink2">
          <Icon name={icon} size={16} />
        </span>
      </div>
      <span className={cn("text-stat font-semibold tabular-nums", danger ? "text-danger-ink" : "text-ink")}>{value}</span>
      {note && <span className="mt-auto text-caption text-ink2">{note}</span>}
    </section>
  );
}
