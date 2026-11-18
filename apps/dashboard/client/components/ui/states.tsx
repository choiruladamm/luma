import type { ReactNode } from "react";
import { useI18n } from "../../i18n";
import { Button } from "./button";
import { Icon, type IconName } from "./icons";

/** Empty: icon tile, title, one sentence, one action (design component 2, State). */
export function EmptyState({ icon, title, children, action }: { icon: IconName; title: string; children?: ReactNode; action?: ReactNode }) {
  return (
    <div className="flex flex-col items-center gap-3 px-6 py-14 text-center">
      <span className="flex size-12 items-center justify-center rounded-tile-lg bg-muted text-ink2">
        <Icon name={icon} size={22} />
      </span>
      <h3 className="m-0 text-card font-semibold">{title}</h3>
      {children && <p className="m-0 max-w-[420px] text-body text-ink2">{children}</p>}
      {action}
    </div>
  );
}

/** Failed load: role=alert, soft-red tile, and a "Coba lagi" (try again) action. */
export function ErrorState({ title, message, onRetry }: { title?: string; message: string; onRetry: () => void }) {
  const { t } = useI18n();
  return (
    <div role="alert" className="flex flex-col items-center gap-3 px-6 py-14 text-center">
      <span className="flex size-12 items-center justify-center rounded-tile-lg bg-danger-soft text-danger-ink">
        <Icon name="alert" size={22} />
      </span>
      <h3 className="m-0 text-card font-semibold">{title ?? t.common.loadFailed}</h3>
      <p className="m-0 max-w-[420px] text-body text-ink2">{message}</p>
      <Button variant="secondary" icon="refresh" onClick={onRetry}>
        {t.common.retry}
      </Button>
    </div>
  );
}
