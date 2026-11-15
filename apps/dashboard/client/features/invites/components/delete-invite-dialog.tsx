import { Button } from "../../../components/ui/button";
import { ConfirmFooter, Dialog } from "../../../components/ui/dialog";

export function DeleteInviteDialog({ code, onClose, onConfirm, pending }: { code: string | null; onClose: () => void; onConfirm: () => void; pending: boolean }) {
  return (
    <Dialog
      open={code !== null}
      onClose={onClose}
      title="Hapus kode ini?"
      description="Kode yang belum dipakai ini gak bisa dipakai daftar lagi."
      icon="x"
      tone="danger"
      footer={
        <ConfirmFooter>
          <Button variant="secondary" onClick={onClose} autoFocus>
            Batal
          </Button>
          <Button variant="danger" icon="x" onClick={onConfirm} disabled={pending}>
            {pending ? "Lagi hapus…" : "Hapus kode"}
          </Button>
        </ConfirmFooter>
      }
    >
      <div className="flex justify-center rounded-row bg-canvas p-4 font-mono text-card font-semibold shadow-[inset_0_0_0_1px_var(--c-track)]">{code}</div>
    </Dialog>
  );
}
