import { type SkeletonColumn, TableSkeleton } from "../../../components/ui/data-table";
import { Skeleton } from "../../../components/ui/skeleton";
import { useI18n } from "../../../i18n";

const USED_BY_WIDTHS = [0, 0, 152, 128, 176];

/**
 * No loading board for Invites (Undangan): same rule as board 13 (design component 2, State). Real headers of
 * invite-columns.tsx, sand blocks for the code, status chip, user, date, and the two actions.
 */
export function InvitesTableSkeleton({ rows = 5 }: { rows?: number }) {
  const { t } = useI18n();
  const columns: SkeletonColumn[] = [
    { header: t.invites.code, cell: () => <Skeleton className="h-3.5 w-[168px]" /> },
    { header: t.invites.created, cell: () => <Skeleton className="h-3 w-20" /> },
    { header: t.invites.status, cell: () => <Skeleton className="h-6 w-[104px]" /> },
    {
      header: t.invites.usedBy,
      cell: (r) =>
        USED_BY_WIDTHS[r % USED_BY_WIDTHS.length] ? (
          <Skeleton className="h-3" style={{ width: USED_BY_WIDTHS[r % USED_BY_WIDTHS.length] }} />
        ) : (
          <Skeleton className="h-3 w-3" />
        ),
    },
    { header: t.invites.usedAt, cell: () => <Skeleton className="h-3 w-20" /> },
    {
      header: t.invites.actions,
      srOnly: true,
      cell: () => (
        <span className="flex justify-end gap-1.5">
          <Skeleton className="size-11" />
          <Skeleton className="size-11" />
        </span>
      ),
    },
  ];
  return (
    <TableSkeleton
      label={t.invites.loading}
      columns={columns}
      rows={rows}
      minWidth={880}
      card={<InviteCardSkeleton />}
    />
  );
}

/** Phone row (InviteCard): code + status, then the two action buttons. */
function InviteCardSkeleton() {
  return (
    <div className="flex flex-col gap-2">
      <div className="flex items-center justify-between gap-3">
        <Skeleton className="h-4 w-44" />
        <Skeleton className="h-6 w-[104px]" />
      </div>
      <Skeleton className="h-3 w-48" />
      <div className="flex gap-2">
        <Skeleton className="size-11" />
        <Skeleton className="size-11" />
      </div>
    </div>
  );
}
