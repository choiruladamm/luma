import { useMemo } from "react";
import { PageHeader } from "../../../components/layout/page-header";
import { UpdatedAt } from "../../../components/layout/updated-at";
import { ButtonLink } from "../../../components/ui/button";
import { StatCard } from "../../../components/ui/card";
import { DataTable } from "../../../components/ui/data-table";
import { ErrorState } from "../../../components/ui/states";
import { formatBytes, formatNumber } from "../../../lib/format";
import { USER_NUMERIC, UserCard, userColumns } from "../../users/components/user-columns";
import { UsersTableSkeleton } from "../../users/components/users-table-skeleton";
import { useUsers } from "../../users/queries/use-users";
import { AiSpendCard } from "../components/ai-spend-card";
import { CardSkeleton, OverviewStatsSkeleton } from "../components/overview-skeleton";
import { ServicesCard } from "../components/services-card";
import { StorageCard } from "../components/storage-card";
import { SyncCard } from "../components/sync-card";
import { useOverview } from "../queries/use-overview";

const RECENT = 5;
const pct = (part: number, whole: number) => (whole > 0 ? `${Math.round((part / whole) * 100)}%` : "0%");

/** Board 01 Ringkasan (+ 12 loading). */
export function OverviewPage() {
  const overview = useOverview();
  const recent = useUsers("");
  const data = overview.data;
  const recentRows = useMemo(() => recent.data?.pages[0]?.items.slice(0, RECENT) ?? [], [recent.data]);
  const refresh = () => void Promise.all([overview.refetch(), recent.refetch()]);

  return (
    <>
      <PageHeader title="Ringkasan" actions={<UpdatedAt at={overview.dataUpdatedAt} onRefresh={refresh} refreshing={overview.isFetching} />} />
      {overview.isError && !data ? (
        <section className="rounded-card bg-sheet">
          <ErrorState message={overview.error.message} onRetry={() => void overview.refetch()} />
        </section>
      ) : !data ? (
        <>
          <OverviewStatsSkeleton />
          <div className="flex flex-wrap gap-4">
            <CardSkeleton title="Sync" className="flex-[2_1_480px]" />
            <CardSkeleton title="Penyimpanan" className="flex-[1_1_320px]" />
          </div>
        </>
      ) : (
        <>
          <div className="grid grid-cols-[repeat(auto-fit,minmax(200px,1fr))] gap-4">
            <StatCard label="User terdaftar" icon="users" value={formatNumber(data.users.total)} note={<><strong className="text-ink">+{formatNumber(data.users.new7d)}</strong> dalam 7 hari</>} />
            <StatCard label="Baru 7 hari" icon="clock" value={formatNumber(data.users.new7d)} note={`dari ${formatNumber(data.users.total)} user`} />
            <StatCard label="Di-ban" icon="ban" value={formatNumber(data.users.banned)} danger={data.users.banned > 0} note={`${pct(data.users.banned, data.users.total)} dari semua user`} />
            <StatCard label="Penyimpanan" icon="drive" value={formatBytes(data.storage.r2Bytes + data.storage.syncBytes)} note="file buku + data sync" />
            <StatCard label="Kode undangan" icon="ticket" value={formatNumber(data.invites.unused)} note="belum dipakai" />
          </div>
          <div className="flex flex-wrap items-start gap-4">
            <div className="flex min-w-0 flex-[2_1_480px] flex-col gap-4">
              <SyncCard rows={data.syncToday.rows} limit={data.syncToday.limit} />
              <AiSpendCard ai={data.ai} />
            </div>
            <div className="flex min-w-0 flex-[1_1_320px] flex-col gap-4">
              <StorageCard r2Bytes={data.storage.r2Bytes} syncBytes={data.storage.syncBytes} />
              <ServicesCard flags={data.flags} />
            </div>
          </div>
        </>
      )}
      <section aria-labelledby="h-baru" className="overflow-hidden rounded-card bg-sheet">
        <div className="flex min-h-11 flex-wrap items-center justify-between gap-3 px-6 pt-4 pb-2">
          <h2 id="h-baru" className="m-0 text-card font-semibold">
            Baru daftar
          </h2>
          <ButtonLink to="/users" variant="secondary" icon="arrow">
            Semua user
          </ButtonLink>
        </div>
        {recent.isError ? (
          <ErrorState message={recent.error.message} onRetry={() => void recent.refetch()} />
        ) : !recent.data ? (
          <UsersTableSkeleton rows={RECENT} />
        ) : (
          <DataTable
            label="User yang baru daftar"
            columns={userColumns}
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
