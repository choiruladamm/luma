import { Avatar } from "../../../components/ui/avatar";
import { Button } from "../../../components/ui/button";
import { ConfirmFooter, Dialog } from "../../../components/ui/dialog";
import { Icon, type IconName } from "../../../components/ui/icons";
import { formatDate } from "../../../lib/format";
import type { UserDetail } from "../api/users-api";
import { UserStatusChip } from "./user-columns";

// Ban in Luma only revokes the subsidized AI quota (docs/dashboard.md, Scope MVP); the board's
// "can't sign in or sync" copy is corrected here.
const EFFECTS: [IconName, string, boolean][] = [
  ["x", "Key AI gratisnya langsung dicabut", true],
  ["check", "Masuk, backup, dan sync tetap jalan", false],
  ["check", "Ban bisa dibuka kapan aja dari halaman ini", false],
];

export function BanDialog({ user, open, onClose, onConfirm, pending }: { user: UserDetail; open: boolean; onClose: () => void; onConfirm: () => void; pending: boolean }) {
  return (
    <Dialog
      open={open}
      onClose={onClose}
      title="Ban user ini?"
      description="Kuota AI gratisnya dicabut sampai ban dibuka."
      icon="ban"
      tone="danger"
      footer={
        <ConfirmFooter>
          <Button variant="secondary" onClick={onClose} autoFocus>
            Batal
          </Button>
          <Button variant="danger" icon="ban" onClick={onConfirm} disabled={pending}>
            {pending ? "Lagi nge-ban…" : "Ban user"}
          </Button>
        </ConfirmFooter>
      }
    >
      <div className="flex items-center gap-3 rounded-row bg-canvas p-3 shadow-[inset_0_0_0_1px_var(--c-track)]">
        <Avatar seed={user.email} label={user.name || user.email} size={40} />
        <div className="flex min-w-0 flex-1 flex-col gap-0.5">
          <span className="text-body font-medium [overflow-wrap:anywhere]">{user.email}</span>
          <span className="text-caption text-ink2">
            {user.name ? `${user.name} · ` : ""}daftar {formatDate(user.createdAt)}
          </span>
        </div>
        <UserStatusChip banned={user.banned} />
      </div>
      <div className="flex flex-col gap-1">
        <span className="text-caption font-medium text-ink2">Yang terjadi</span>
        <ul className="m-0 flex list-none flex-col p-0">
          {EFFECTS.map(([icon, text, bad]) => (
            <li key={text} className="flex min-h-10 items-center gap-3">
              <span aria-hidden="true" className={`flex size-7 flex-none items-center justify-center rounded-[9px] ${bad ? "bg-danger-soft text-danger-ink" : "bg-muted text-ink"}`}>
                <Icon name={icon} size={14} strokeWidth={2.2} />
              </span>
              <span className="text-body">{text}</span>
            </li>
          ))}
        </ul>
      </div>
    </Dialog>
  );
}
