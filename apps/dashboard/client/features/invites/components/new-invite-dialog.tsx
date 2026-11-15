import { Button } from "../../../components/ui/button";
import { Chip } from "../../../components/ui/chip";
import { Dialog, ResultFooter } from "../../../components/ui/dialog";
import { Icon } from "../../../components/ui/icons";
import { useI18n } from "../../../i18n";
import { formatDateTime } from "../../../lib/format";

/**
 * Board 09: the new code on an invite ticket (ink 1.5 outline, dashed tear with notches, pink
 * stabilo), copy status announced (aria-live), two equal buttons; yellow turns "Udah disalin".
 */
export function NewInviteDialog({ code, createdAt, copied, onCopy, onClose }: { code: string | null; createdAt: string; copied: boolean; onCopy: () => void; onClose: () => void }) {
  const { locale } = useI18n();
  return (
    <Dialog
      open={code !== null}
      onClose={onClose}
      title="Kode baru siap"
      description="Kirim ke orang yang mau lo undang."
      icon="ticket"
      footer={
        <ResultFooter>
          <Button variant="secondary" size="lg" onClick={onClose}>
            Selesai
          </Button>
          <Button variant="primary" size="lg" icon={copied ? "check" : "copy"} onClick={onCopy} autoFocus>
            {copied ? "Udah disalin" : "Salin kode"}
          </Button>
        </ResultFooter>
      }
    >
      <div className="relative overflow-hidden rounded-card bg-canvas shadow-[inset_0_0_0_1.5px_var(--c-outline)]">
        <div className="flex items-center justify-between gap-3 px-5 py-[18px]">
          <span className="inline-flex items-center gap-2 text-caption font-medium">
            <Icon name="ticket" size={16} />
            Undangan beta Luma
          </span>
          <Chip tone="sheet">Sekali pakai</Chip>
        </div>
        <div className="relative mx-[22px] h-0 border-t-[1.5px] border-dashed border-line">
          <span aria-hidden="true" className="absolute -top-[13px] -left-[35px] size-[26px] rounded-full bg-sheet shadow-[inset_0_0_0_1.5px_var(--c-outline)]" />
          <span aria-hidden="true" className="absolute -top-[13px] -right-[35px] size-[26px] rounded-full bg-sheet shadow-[inset_0_0_0_1.5px_var(--c-outline)]" />
        </div>
        <div className="flex flex-col items-center gap-2 px-5 pt-[22px] pb-[26px]">
          <span className="text-caption text-ink2">Kode undangan</span>
          <span className="bg-[linear-gradient(transparent_58%,var(--c-pink)_58%,var(--c-pink)_94%,transparent_94%)] px-2 text-center font-mono text-[clamp(22px,6vw,32px)] leading-[1.1] font-semibold tracking-[0.06em] tabular-nums [overflow-wrap:anywhere]">
            {code}
          </span>
          <span className="text-caption text-ink2">Dibuat {formatDateTime(createdAt, locale)}</span>
        </div>
      </div>
      <div aria-live="polite" className="flex min-h-6 items-center justify-center">
        {copied ? (
          <span className="inline-flex items-center gap-1.5 text-caption font-medium">
            <Icon name="check" size={16} />
            Udah disalin ke clipboard
          </span>
        ) : (
          <span className="text-center text-caption text-ink2">Tinggal salin, terus kirim. Kodenya tetap ada di daftar Undangan.</span>
        )}
      </div>
    </Dialog>
  );
}
