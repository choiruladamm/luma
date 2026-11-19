import { Link } from "react-router";
import { Chip } from "../../../components/ui/chip";
import { columnHelper } from "../../../components/ui/data-table";
import { Icon } from "../../../components/ui/icons";
import { type I18n, useI18n } from "../../../i18n";
import { formatDate } from "../../../lib/format";
import type { InviteItem } from "../api/invites-api";

const h = columnHelper<InviteItem>();

export function InviteStatusChip({ used }: { used: boolean }) {
  const { t } = useI18n();
  return used ? (
    <Chip dot="filled">{t.invites.used}</Chip>
  ) : (
    <Chip tone="sheet" dot="hollow" className="shadow-[inset_0_0_0_1px_var(--c-track)]">
      {t.invites.unused}
    </Chip>
  );
}

export function UsedBy({ invite }: { invite: InviteItem }) {
  const { t } = useI18n();
  if (!invite.used_by)
    return <span className="text-ink2">{invite.used_at ? t.invites.accountDeleted : "—"}</span>;
  return (
    <Link to={`/users/${invite.used_by.id}`} className="text-ink no-underline hover:underline">
      {invite.used_by.email}
    </Link>
  );
}

/** Columns for board 08 plus "Dibuat" ("—" for codes made before it was recorded). Actions come from the page. */
export function inviteColumns(i18n: I18n, actions: (invite: InviteItem) => React.ReactNode) {
  return h.columns([
    h.accessor("code", {
      header: i18n.t.invites.code,
      cell: (info) => <span className="font-mono text-body font-medium">{info.getValue()}</span>,
    }),
    h.accessor("created_at", {
      id: "createdAt",
      header: i18n.t.invites.created,
      cell: (info) => (info.getValue() ? formatDate(info.getValue()!, i18n.locale) : "—"),
    }),
    h.accessor("used_at", {
      id: "status",
      header: i18n.t.invites.status,
      cell: (info) => <InviteStatusChip used={info.getValue() !== null} />,
    }),
    h.accessor("used_by", {
      header: i18n.t.invites.usedBy,
      cell: (info) => <UsedBy invite={info.row.original} />,
    }),
    h.accessor("used_at", {
      id: "usedAt",
      header: i18n.t.invites.usedAt,
      cell: (info) => (info.getValue() ? formatDate(info.getValue()!, i18n.locale) : "—"),
    }),
    h.display({
      id: "actions",
      header: () => <span className="sr-only">{i18n.t.invites.actions}</span>,
      cell: (info) => actions(info.row.original),
    }),
  ]);
}

export function InviteCard({ invite, actions }: { invite: InviteItem; actions: React.ReactNode }) {
  const { t, locale } = useI18n();
  return (
    <div className="flex flex-col gap-2">
      <div className="flex items-center justify-between gap-3">
        <span className="font-mono text-card font-semibold">{invite.code}</span>
        <InviteStatusChip used={invite.used_at !== null} />
      </div>
      {invite.created_at && (
        <span className="text-caption text-ink2">
          {t.invites.createdAt(formatDate(invite.created_at, locale))}
        </span>
      )}
      {invite.used_at && (
        <span className="flex min-w-0 items-center gap-1.5 text-caption text-ink2">
          <Icon name="user" size={14} />
          <span className="min-w-0 truncate">
            <UsedBy invite={invite} />
          </span>
          <span className="flex-none">· {formatDate(invite.used_at, locale)}</span>
        </span>
      )}
      <div className="flex gap-2">{actions}</div>
    </div>
  );
}
