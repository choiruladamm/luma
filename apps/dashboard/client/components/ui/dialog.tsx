import { type ReactNode, useEffect, useRef } from "react";
import { useI18n } from "../../i18n";
import { cn } from "../../lib/cn";
import { IconButton } from "./button";
import { Icon, type IconName } from "./icons";

/**
 * Komponen 1, Dialog: width 480, radius 28, sheet shadow over an ink scrim. Native <dialog>
 * with showModal() gives the focus trap, inert background, and Esc-to-close.
 */
export function Dialog({ open, onClose, title, description, icon, tone = "neutral", children, footer }: { open: boolean; onClose: () => void; title: string; description?: ReactNode; icon: IconName; tone?: "neutral" | "danger"; children?: ReactNode; footer: ReactNode }) {
  const ref = useRef<HTMLDialogElement>(null);
  const { t } = useI18n();
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    if (open && !el.open) el.showModal();
    if (!open && el.open) el.close();
  }, [open]);

  return (
    <dialog
      ref={ref}
      aria-labelledby="dialog-title"
      onCancel={(e) => {
        e.preventDefault();
        onClose();
      }}
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
      className="m-auto w-[calc(100%-48px)] max-w-[480px] overflow-hidden rounded-dialog bg-sheet p-0 text-ink shadow-sheet backdrop:bg-scrim"
    >
      {open && (
        <div className="flex flex-col">
          <div className="flex flex-col gap-1 pt-5 pr-5 pl-6">
            <div className="flex items-center gap-3">
              <span aria-hidden="true" className={cn("flex size-8 flex-none items-center justify-center rounded-full", tone === "danger" ? "bg-danger-soft text-danger-ink" : "bg-muted text-ink")}>
                <Icon name={icon} size={16} strokeWidth={2.2} />
              </span>
              <h2 id="dialog-title" className="m-0 min-w-0 flex-1 text-dialog font-semibold">
                {title}
              </h2>
              <IconButton icon="x" label={t.common.closeDialog} onClick={onClose} />
            </div>
            {description && <p className="m-0 ml-11 text-body text-ink2">{description}</p>}
          </div>
          {children && <div className="flex flex-col gap-4 px-6 pt-5">{children}</div>}
          {footer}
        </div>
      )}
    </dialog>
  );
}

/** Footer for destructive confirms: canvas panel, Esc hint left, actions right. */
export function ConfirmFooter({ children }: { children: ReactNode }) {
  const { t } = useI18n();
  return (
    <div className="mt-6 flex flex-wrap items-center justify-between gap-3 border-t border-track bg-canvas px-6 py-4">
      <span className="inline-flex items-center gap-2 text-caption text-ink2">
        <kbd className="inline-flex h-[22px] items-center rounded-[7px] bg-muted px-[7px] font-mono text-chip font-medium text-ink shadow-[inset_0_-1px_0_var(--c-track)]">Esc</kbd>
        {t.common.escToCancel}
      </span>
      <div className="flex flex-wrap gap-2.5">{children}</div>
    </div>
  );
}

/** Footer for result dialogs: two equal buttons, no panel. */
export function ResultFooter({ children }: { children: ReactNode }) {
  return <div className="grid grid-cols-2 gap-2.5 px-6 pt-5 pb-6">{children}</div>;
}
