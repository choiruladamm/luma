import type { ReactNode } from "react";

/** Status banner (danger soft): bold title + detail, action on the right; the text names the state. */
export function Banner({
  title,
  children,
  action,
}: {
  title: string;
  children?: ReactNode;
  action?: ReactNode;
}) {
  return (
    <div
      role="status"
      className="flex flex-wrap items-center gap-3 rounded-row bg-danger-soft px-4 py-3.5"
    >
      <div className="flex min-w-0 flex-[1_1_260px] flex-col gap-0.5">
        <strong className="text-body text-danger-ink">{title}</strong>
        {children && <span className="text-caption text-danger-ink">{children}</span>}
      </div>
      {action}
    </div>
  );
}
