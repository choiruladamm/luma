import { Avatar } from "../../../components/ui/avatar";
import { Chip } from "../../../components/ui/chip";
import { columnHelper } from "../../../components/ui/data-table";
import { type I18n, useI18n } from "../../../i18n";
import { formatBytes, formatDate, formatRelative } from "../../../lib/format";
import type { UserListItem } from "../api/users-api";

const h = columnHelper<UserListItem>();

export function UserStatusChip({ banned }: { banned: boolean }) {
  return banned ? (
    <Chip tone="danger" dot="filled">
      Di-ban
    </Chip>
  ) : (
    <Chip dot="filled">Aktif</Chip>
  );
}

/** The server only knows the subsidized key; an own key lives on the device, so it shows "—". */
export const aiKeyLabel = (hasAiKey: boolean) => (hasAiKey ? "Kuota gratis" : "—");

export function UserIdentity({ user }: { user: Pick<UserListItem, "email" | "name"> }) {
  return (
    <span className="flex min-w-0 items-center gap-3">
      <Avatar seed={user.email} label={user.name || user.email} />
      <span className="flex min-w-0 flex-col gap-0.5">
        <span className="lead truncate text-body font-medium text-ink">{user.email}</span>
        <span className="truncate text-caption text-ink2">{user.name || "—"}</span>
      </span>
    </span>
  );
}

// Komponen 2, Tabel: numbers right-aligned and tabular, empty values "—".
export const userColumns = (i18n: I18n) =>
  h.columns([
  h.accessor("email", { header: "User", cell: (info) => <UserIdentity user={info.row.original} /> }),
  h.accessor("createdAt", { header: "Daftar", cell: (info) => <span className="whitespace-nowrap">{formatDate(info.getValue(), i18n.locale)}</span> }),
  h.accessor("lastActiveAt", { header: "Terakhir aktif", cell: (info) => <span className="whitespace-nowrap">{formatRelative(info.getValue(), i18n)}</span> }),
  h.accessor("r2Bytes", { header: "File", cell: (info) => formatBytes(info.getValue(), i18n.locale) }),
  h.accessor("syncBytes", { header: "Data sync", cell: (info) => formatBytes(info.getValue(), i18n.locale) }),
  h.accessor("hasAiKey", { header: "Key AI", cell: (info) => aiKeyLabel(info.getValue()) }),
  h.accessor("banned", { header: "Status", cell: (info) => <UserStatusChip banned={info.getValue()} /> }),
]);

export const USER_NUMERIC = ["r2Bytes", "syncBytes"];

/** Phone layout of a row: avatar, email, status, then 4 data in a 2-column grid. */
export function UserCard({ user }: { user: UserListItem }) {
  const i18n = useI18n();
  const data: [string, string][] = [
    ["Daftar", formatDate(user.createdAt, i18n.locale)],
    ["Terakhir aktif", formatRelative(user.lastActiveAt, i18n)],
    ["File", formatBytes(user.r2Bytes, i18n.locale)],
    ["Data sync", formatBytes(user.syncBytes, i18n.locale)],
  ];
  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between gap-3 [&>:first-child]:flex-1">
        <UserIdentity user={user} />
        <UserStatusChip banned={user.banned} />
      </div>
      <dl className="m-0 grid grid-cols-2 gap-x-4 gap-y-2">
        {data.map(([k, v]) => (
          <div key={k} className="flex flex-col gap-0.5">
            <dt className="text-caption text-ink2">{k}</dt>
            <dd className="m-0 text-body font-medium tabular-nums">{v}</dd>
          </div>
        ))}
      </dl>
    </div>
  );
}
