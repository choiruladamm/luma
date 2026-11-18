import { type SkeletonColumn, TableSkeleton } from "../../../components/ui/data-table";
import { Skeleton } from "../../../components/ui/skeleton";
import { useI18n } from "../../../i18n";

// Board 13: email widths vary per row so the block reads as a list, not a grid.
const EMAIL_WIDTHS = [168, 140, 184, 152, 176, 132];

/** Board 13: the users table (same columns as user-columns.tsx) with sand blocks for values. */
export function UsersTableSkeleton({ rows = 8 }: { rows?: number }) {
  const { t } = useI18n();
  const columns: SkeletonColumn[] = [
    {
      header: t.users.user,
      cell: (r) => (
        <span className="flex items-center gap-3">
          <Skeleton className="size-9 flex-none" />
          <span className="flex flex-col gap-1.5">
            <Skeleton className="h-3" style={{ width: EMAIL_WIDTHS[r % EMAIL_WIDTHS.length] }} />
            <Skeleton className="h-2.5 w-24" />
          </span>
        </span>
      ),
    },
    { header: t.users.joined, sorted: true, cell: () => <Skeleton className="h-3 w-[84px]" /> },
    { header: t.users.lastActive, cell: () => <Skeleton className="h-3 w-[72px]" /> },
    { header: t.users.files, align: "right", cell: () => <Skeleton className="h-3 w-12" /> },
    { header: t.users.syncData, align: "right", cell: () => <Skeleton className="h-3 w-11" /> },
    { header: t.users.aiKey, cell: () => <Skeleton className="h-3 w-16" /> },
    { header: t.users.status, cell: () => <Skeleton className="h-6 w-[68px]" /> },
  ];
  return (
    <TableSkeleton
      label={t.users.loading}
      columns={columns}
      rows={rows}
      rowLink
      card={<UserCardSkeleton />}
    />
  );
}

/** Phone row (UserCard): avatar, email, status, then the 4 labels with value blocks. */
function UserCardSkeleton() {
  const { t } = useI18n();
  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center gap-3">
        <Skeleton className="size-9 flex-none" />
        <span className="flex flex-1 flex-col gap-1.5">
          <Skeleton className="h-3 w-40" />
          <Skeleton className="h-2.5 w-24" />
        </span>
        <Skeleton className="h-6 w-[68px]" />
      </div>
      <dl className="m-0 grid grid-cols-2 gap-x-4 gap-y-2">
        {[t.users.joined, t.users.lastActive, t.users.files, t.users.syncData].map((label) => (
          <div key={label} className="flex flex-col gap-1.5">
            <dt className="text-caption text-ink2">{label}</dt>
            <dd className="m-0">
              <Skeleton className="h-3 w-20" />
            </dd>
          </div>
        ))}
      </dl>
    </div>
  );
}
