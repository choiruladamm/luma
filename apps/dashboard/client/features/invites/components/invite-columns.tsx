import { Link } from "react-router";
import { Chip } from "../../../components/ui/chip";
import { columnHelper } from "../../../components/ui/data-table";
import { Icon } from "../../../components/ui/icons";
import { formatDate } from "../../../lib/format";
import type { InviteItem } from "../api/invites-api";

const h = columnHelper<InviteItem>();

export function InviteStatusChip({ used }: { used: boolean }) {
  return used ? <Chip dot="filled">Udah dipakai</Chip> : <Chip tone="sheet" dot="hollow" className="shadow-[inset_0_0_0_1px_var(--c-track)]">Belum dipakai</Chip>;
}

export function UsedBy({ invite }: { invite: InviteItem }) {
  if (!invite.usedBy) return <span className="text-ink2">{invite.usedAt ? "Akun udah dihapus" : "—"}</span>;
  return (
    <Link to={`/users/${invite.usedBy.id}`} className="text-ink no-underline hover:underline">
      {invite.usedBy.email}
    </Link>
  );
}

/** Columns for board 08 (no "Dibuat": invite codes have no created_at). Actions come from the page. */
export function inviteColumns(actions: (invite: InviteItem) => React.ReactNode) {
  return h.columns([
    h.accessor("code", { header: "Kode", cell: (info) => <span className="font-mono text-body font-medium">{info.getValue()}</span> }),
    h.accessor("usedAt", { id: "status", header: "Status", cell: (info) => <InviteStatusChip used={info.getValue() !== null} /> }),
    h.accessor("usedBy", { header: "Dipakai oleh", cell: (info) => <UsedBy invite={info.row.original} /> }),
    h.accessor("usedAt", { id: "usedAt", header: "Tanggal dipakai", cell: (info) => (info.getValue() ? formatDate(info.getValue()!) : "—") }),
    h.display({ id: "actions", header: () => <span className="sr-only">Aksi</span>, cell: (info) => actions(info.row.original) }),
  ]);
}

export function InviteCard({ invite, actions }: { invite: InviteItem; actions: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-2">
      <div className="flex items-center justify-between gap-3">
        <span className="font-mono text-card font-semibold">{invite.code}</span>
        <InviteStatusChip used={invite.usedAt !== null} />
      </div>
      {invite.usedAt && (
        <span className="flex items-center gap-1.5 text-caption text-ink2">
          <Icon name="user" size={14} />
          <UsedBy invite={invite} /> · {formatDate(invite.usedAt)}
        </span>
      )}
      <div className="flex gap-2">{actions}</div>
    </div>
  );
}
