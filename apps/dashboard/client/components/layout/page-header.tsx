import type { ReactNode } from "react";

/**
 * Page title (Bricolage 28/600) with an optional count/subtitle, `meta` (data time + refresh)
 * and `actions` (primary buttons). Desktop: one row, meta before actions. Phone: the title and
 * the actions share the first row, meta takes its own row below.
 */
export function PageHeader({
  title,
  after,
  meta,
  actions,
}: {
  title: ReactNode;
  after?: ReactNode;
  meta?: ReactNode;
  actions?: ReactNode;
}) {
  return (
    <div className="flex flex-wrap items-center gap-3">
      <div className="flex min-w-0 flex-1 flex-wrap items-center gap-3">
        <h1 className="m-0 font-display text-title font-semibold">{title}</h1>
        {after}
      </div>
      {meta && <div className="order-3 basis-full md:order-2 md:basis-auto">{meta}</div>}
      {actions && (
        <div className="order-2 flex flex-wrap items-center gap-2 md:order-3">{actions}</div>
      )}
    </div>
  );
}
