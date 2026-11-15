import { useMemo } from "react";
import { PageHeader } from "../../../components/layout/page-header";
import { UpdatedAt } from "../../../components/layout/updated-at";
import { ButtonLink } from "../../../components/ui/button";
import { StatCard } from "../../../components/ui/card";
import { DataTable } from "../../../components/ui/data-table";
import { ErrorState } from "../../../components/ui/states";
import { useI18n } from "../../../i18n";
import { errorText } from "../../../lib/api-error";
import { formatBytes, formatNumber } from "../../../lib/format";
import { USER_NUMERIC, UserCard, userColumns } from "../../users/components/user-columns";
import { UsersTableSkeleton } from "../../users/components/users-table-skeleton";
import { useUsers } from "../../users/queries/use-users";
import { AiSpendCard } from "../components/ai-spend-card";
import { StatNoteSkeleton, StatValueSkeleton } from "../components/overview-skeleton";
import { ServicesCard } from "../components/services-card";
import { StorageCard } from "../components/storage-card";
import { SyncCard } from "../components/sync-card";
import { useOverview } from "../queries/use-overview";

const RECENT = 5;
const pct = (part: number, whole: number) => (whole > 0 ? `${Math.round((part / whole) * 100)}%` : "0%");

/** Board 01 Ringkasan (+ 12 loading). */
export function OverviewPage() {
  const overview = useOverview();
  const i18n = useI18n();
  const { t, locale } = i18n;
  const columns = useMemo(() => userColumns(i18n), [i18n]);
  const recent = useUsers("");
  const data = overview.data;
  const recentRows = useMemo(() => recent.data?.pages[0]?.items.slice(0, RECENT) ?? [], [recent.data]);
  const refresh = () => void Promise.all([overview.refetch(), recent.refetch()]);

  return (
    <>
      <PageHeader title={t.shell.overview} actions={<UpdatedAt at={overview.dataUpdatedAt} onRefresh={refresh} refreshing={overview.isFetching} />} />
      {overview.isError && !data ? (
        <section className="rounded-card bg-sheet">
          <ErrorState message={errorText(overview.error, t)} onRetry={() => void overview.refetch()} />
        </section>
      ) : (
        <>
          {/* Board 12: while loading, the real labels and icons stay and only the values pulse. */}
          <div aria-busy={!data || undefined} className="grid grid-cols-[repeat(auto-fit,minmax(200px,1fr))] gap-4">
            <StatCard label={t.overview.registered} icon="users" value={data ? formatNumber(data.users.total, locale) : <StatValueSkeleton />} note={data ? <><strong className="text-ink">+{formatNumber(data.users.new7d, locale)}</strong> {t.overview.inWeek}</> : <StatNoteSkeleton />} />
            <StatCard label={t.overview.newWeek} icon="clock" value={data ? formatNumber(data.users.new7d, locale) : <StatValueSkeleton />} note={data ? t.overview.ofUsers(formatNumber(data.users.total, locale), data.users.total) : <StatNoteSkeleton />} />
            <StatCard label={t.overview.banned} icon="ban" value={data ? formatNumber(data.users.banned, locale) : <StatValueSkeleton />} danger={!!data && data.users.banned > 0} note={data ? t.overview.bannedShare(pct(data.users.banned, data.users.total)) : <StatNoteSkeleton />} />
            <StatCard label={t.overview.storage} icon="drive" value={data ? formatBytes(data.storage.r2Bytes + data.storage.syncBytes, locale) : <StatValueSkeleton />} note={data ? t.overview.storageNote : <StatNoteSkeleton />} />
            <StatCard label={t.overview.invites} icon="ticket" value={data ? formatNumber(data.invites.unused, locale) : <StatValueSkeleton />} note={data ? t.overview.unused : <StatNoteSkeleton />} />
          </div>
          <div className="flex flex-wrap items-start gap-4">
            <div className="flex min-w-0 flex-[2_1_480px] flex-col gap-4">
              <SyncCard data={data?.syncToday} />
              <AiSpendCard ai={data?.ai} />
            </div>
            <div className="flex min-w-0 flex-[1_1_320px] flex-col gap-4">
              <StorageCard data={data?.storage} />
              <ServicesCard flags={data?.flags} />
            </div>
          </div>
        </>
      )}
      <section aria-labelledby="h-baru" className="overflow-hidden rounded-card bg-sheet">
        <div className="flex min-h-11 flex-wrap items-center justify-between gap-3 px-6 pt-4 pb-2">
          <h2 id="h-baru" className="m-0 text-card font-semibold">
            {t.overview.recent}
          </h2>
          <ButtonLink to="/users" variant="secondary" icon="arrow">
            {t.overview.allUsers}
          </ButtonLink>
        </div>
        {recent.isError ? (
          <ErrorState message={errorText(recent.error, t)} onRetry={() => void recent.refetch()} />
        ) : !recent.data ? (
          <UsersTableSkeleton rows={RECENT} />
        ) : (
          <DataTable
            label={t.overview.recentTable}
            columns={columns}
            data={recentRows}
            rowHref={(u) => `/users/${u.id}`}
            numeric={USER_NUMERIC}
            renderCard={(u) => <UserCard user={u} />}
          />
        )}
      </section>
    </>
  );
}
