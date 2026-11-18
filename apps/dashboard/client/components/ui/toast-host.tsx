import { useEffect, useState } from "react";
import { useI18n } from "../../i18n";
import { cn } from "../../lib/cn";
import { useToastStore } from "../../stores/toast-store";
import { Icon } from "./icons";

/**
 * Design component 2, Toast: bottom center, 32 from the edge. Auto-hides after 2.5s (5s with an
 * action), pauses on hover; errors stay until closed.
 */
export function ToastHost() {
  const { toast, dismiss } = useToastStore();
  const [hovered, setHovered] = useState(false);
  const { t } = useI18n();

  useEffect(() => {
    if (!toast || toast.tone === "error" || hovered) return;
    const timer = setTimeout(() => dismiss(toast.id), toast.action ? 5000 : 2500);
    return () => clearTimeout(timer);
  }, [toast, hovered, dismiss]);

  return (
    <div className="pointer-events-none fixed inset-x-0 bottom-[calc(96px+env(safe-area-inset-bottom))] z-50 md:bottom-8 flex justify-center px-4" aria-live="polite">
      {toast && (
        <div
          role={toast.tone === "error" ? "alert" : "status"}
          onMouseEnter={() => setHovered(true)}
          onMouseLeave={() => setHovered(false)}
          className="pointer-events-auto inline-flex min-h-12 items-center gap-2.5 rounded-menu bg-toast py-1 pr-2 pl-3.5 text-body font-medium text-toast-ink shadow-toast"
        >
          <span aria-hidden="true" className={cn("flex size-6 flex-none items-center justify-center rounded-full", toast.tone === "success" && "bg-accent text-on-accent", toast.tone === "error" && "bg-danger-soft text-danger-ink", toast.tone === "info" && "bg-[#46423a] text-toast-ink")}>
            <Icon name={toast.tone === "error" ? "alert" : toast.tone === "info" ? "refresh" : "check"} size={14} strokeWidth={2.2} />
          </span>
          <span className="pr-1.5">{toast.message}</span>
          {toast.action && (
            <button
              type="button"
              onClick={() => {
                toast.action?.onClick();
                dismiss(toast.id);
              }}
              className="h-10 rounded-[20px] bg-accent px-3.5 text-body font-medium text-on-accent"
            >
              {toast.action.label}
            </button>
          )}
          {toast.tone === "error" && (
            <button type="button" aria-label={t.common.close} onClick={() => dismiss(toast.id)} className="flex size-10 items-center justify-center rounded-full hover:bg-white/10">
              <Icon name="x" size={16} />
            </button>
          )}
        </div>
      )}
    </div>
  );
}
