import type { ReactNode } from "react";

/** Page title (Bricolage 28/600) with optional count/subtitle and actions on the right. */
export function PageHeader({ title, after, actions }: { title: ReactNode; after?: ReactNode; actions?: ReactNode }) {
  return (
    <div className="flex flex-wrap items-center justify-between gap-3">
      <div className="flex flex-wrap items-center gap-3">
        <h1 className="m-0 font-display text-title font-semibold">{title}</h1>
        {after}
      </div>
      {actions && <div className="flex flex-wrap items-center gap-2">{actions}</div>}
    </div>
  );
}
