import { Avatar } from "../../../components/ui/avatar";
import { Button } from "../../../components/ui/button";
import { ConfirmFooter, Dialog } from "../../../components/ui/dialog";
import { Icon, type IconName } from "../../../components/ui/icons";
import { useI18n } from "../../../i18n";
import { formatDate } from "../../../lib/format";
import type { UserDetail } from "../api/users-api";
import { UserStatusChip } from "./user-columns";

// Ban in Luma only revokes the subsidized AI quota (docs/backend.md, AI subsidy); the board's
// "can't sign in or sync" copy is corrected here.
const EFFECTS: [IconName, "effectKey" | "effectKeeps" | "effectUndo", boolean][] = [
  ["x", "effectKey", true],
  ["check", "effectKeeps", false],
  ["check", "effectUndo", false],
];

export function BanDialog({ user, open, onClose, onConfirm, pending }: { user: UserDetail; open: boolean; onClose: () => void; onConfirm: () => void; pending: boolean }) {
  const { t, locale } = useI18n();
  return (
    <Dialog
      open={open}
      onClose={onClose}
      title={t.userDetail.banConfirm}
      description={t.userDetail.banConfirmBody}
      icon="ban"
      tone="danger"
      footer={
        <ConfirmFooter>
          <Button variant="secondary" onClick={onClose} autoFocus>
            {t.common.cancel}
          </Button>
          <Button variant="danger" icon="ban" onClick={onConfirm} loading={pending}>
            {t.userDetail.ban}
          </Button>
        </ConfirmFooter>
      }
    >
      <div className="flex items-center gap-3 rounded-row bg-canvas p-3 shadow-[inset_0_0_0_1px_var(--c-track)]">
        <Avatar seed={user.email} label={user.name || user.email} size={40} />
        <div className="flex min-w-0 flex-1 flex-col gap-0.5">
          <span className="text-body font-medium [overflow-wrap:anywhere]">{user.email}</span>
          <span className="text-caption text-ink2">
            {user.name ? `${user.name} · ` : ""}
            {t.userDetail.joinedOn(formatDate(user.createdAt, locale))}
          </span>
        </div>
        <UserStatusChip banned={user.banned} />
      </div>
      <div className="flex flex-col gap-1">
        <span className="text-caption font-medium text-ink2">{t.userDetail.effects}</span>
        <ul className="m-0 flex list-none flex-col p-0">
          {EFFECTS.map(([icon, key, bad]) => (
            <li key={key} className="flex min-h-10 items-center gap-3">
              <span aria-hidden="true" className={`flex size-7 flex-none items-center justify-center rounded-[9px] ${bad ? "bg-danger-soft text-danger-ink" : "bg-muted text-ink"}`}>
                <Icon name={icon} size={14} strokeWidth={2.2} />
              </span>
              <span className="text-body">{t.userDetail[key]}</span>
            </li>
          ))}
        </ul>
      </div>
    </Dialog>
  );
}
