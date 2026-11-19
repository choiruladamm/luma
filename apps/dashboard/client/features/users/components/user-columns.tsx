import { Avatar } from "../../../components/ui/avatar";
import { Chip } from "../../../components/ui/chip";
import { columnHelper } from "../../../components/ui/data-table";
import { Highlight } from "../../../components/ui/highlight";
import { type I18n, useI18n } from "../../../i18n";
import { formatBytes, formatDate, formatRelative } from "../../../lib/format";
import type { UserListItem } from "../api/users-api";

const h = columnHelper<UserListItem>();

export function UserStatusChip({ banned }: { banned: boolean }) {
  const { t } = useI18n();
  return banned ? (
    <Chip tone="danger" dot="filled">
      {t.users.banned}
    </Chip>
  ) : (
    <Chip dot="filled">{t.users.active}</Chip>
  );
}

/** The server only knows the subsidized key; an own key lives on the device, so it shows "—". */
export const aiKeyLabel = (hasAiKey: boolean, t: I18n["t"]) => (hasAiKey ? t.users.freeQuota : "—");

/** `q`: the search text, marked where it matches the email or name. */
export function UserIdentity({
  user,
  q,
}: {
  user: Pick<UserListItem, "email" | "name">;
  q?: string;
}) {
  // One mark per row: the email when it matches, otherwise the name.
  const inEmail = !!q && user.email.toLowerCase().includes(q.toLowerCase());
  return (
    <span className="flex min-w-0 items-center gap-3">
      <Avatar seed={user.email} label={user.name || user.email} />
      <span className="flex min-w-0 flex-col gap-0.5">
        <span className="lead truncate text-body font-medium text-ink">
          <Highlight text={user.email} q={q} />
        </span>
        <span className="truncate text-caption text-ink2">
          {user.name ? <Highlight text={user.name} q={inEmail ? undefined : q} /> : "—"}
        </span>
      </span>
    </span>
  );
}

// Design component 2, Table: numbers right-aligned and tabular, empty values "—".
export const userColumns = (i18n: I18n, q?: string) =>
  h.columns([
    h.accessor("email", {
      header: i18n.t.users.user,
      cell: (info) => <UserIdentity user={info.row.original} q={q} />,
    }),
    h.accessor("created_at", {
      header: i18n.t.users.joined,
      cell: (info) => (
        <span className="whitespace-nowrap">{formatDate(info.getValue(), i18n.locale)}</span>
      ),
    }),
    h.accessor("last_active_at", {
      header: i18n.t.users.lastActive,
      cell: (info) => (
        <span className="whitespace-nowrap">{formatRelative(info.getValue(), i18n)}</span>
      ),
    }),
    h.accessor("r2_bytes", {
      header: i18n.t.users.files,
      cell: (info) => formatBytes(info.getValue(), i18n.locale),
    }),
    h.accessor("sync_bytes", {
      header: i18n.t.users.syncData,
      cell: (info) => formatBytes(info.getValue(), i18n.locale),
    }),
    h.accessor("has_ai_key", {
      header: i18n.t.users.aiKey,
      cell: (info) => aiKeyLabel(info.getValue(), i18n.t),
    }),
    h.accessor("banned", {
      header: i18n.t.users.status,
      cell: (info) => <UserStatusChip banned={info.getValue()} />,
    }),
  ]);

export const USER_NUMERIC = ["r2_bytes", "sync_bytes"];

/** Phone layout of a row: avatar, email, status, then 4 data in a 2-column grid. */
export function UserCard({ user, q }: { user: UserListItem; q?: string }) {
  const i18n = useI18n();
  const data: [string, string][] = [
    [i18n.t.users.joined, formatDate(user.created_at, i18n.locale)],
    [i18n.t.users.lastActive, formatRelative(user.last_active_at, i18n)],
    [i18n.t.users.files, formatBytes(user.r2_bytes, i18n.locale)],
    [i18n.t.users.syncData, formatBytes(user.sync_bytes, i18n.locale)],
  ];
  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between gap-3 [&>:first-child]:flex-1">
        <UserIdentity user={user} q={q} />
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
