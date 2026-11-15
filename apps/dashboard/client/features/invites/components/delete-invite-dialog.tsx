import { Button } from "../../../components/ui/button";
import { ConfirmFooter, Dialog } from "../../../components/ui/dialog";
import { useI18n } from "../../../i18n";

export function DeleteInviteDialog({ code, onClose, onConfirm, pending }: { code: string | null; onClose: () => void; onConfirm: () => void; pending: boolean }) {
  const { t } = useI18n();
  return (
    <Dialog
      open={code !== null}
      onClose={onClose}
      title={t.invites.deleteTitle}
      description={t.invites.deleteBody}
      icon="x"
      tone="danger"
      footer={
        <ConfirmFooter>
          <Button variant="secondary" onClick={onClose} autoFocus>
            {t.common.cancel}
          </Button>
          <Button variant="danger" icon="x" onClick={onConfirm} disabled={pending}>
            {pending ? t.invites.deleting : t.invites.delete}
          </Button>
        </ConfirmFooter>
      }
    >
      <div className="flex justify-center rounded-row bg-canvas p-4 font-mono text-card font-semibold shadow-[inset_0_0_0_1px_var(--c-track)]">{code}</div>
    </Dialog>
  );
}
