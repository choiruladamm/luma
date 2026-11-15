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
      ) : (
        <>
          {/* Board 12: while loading, the real labels and icons stay and only the values pulse. */}
          <div aria-busy={!data || undefined} className="grid grid-cols-[repeat(auto-fit,minmax(200px,1fr))] gap-4">
            <StatCard label="User terdaftar" icon="users" value={data ? formatNumber(data.users.total) : <StatValueSkeleton />} note={data ? <><strong className="text-ink">+{formatNumber(data.users.new7d)}</strong> dalam 7 hari</> : <StatNoteSkeleton />} />
            <StatCard label="Baru 7 hari" icon="clock" value={data ? formatNumber(data.users.new7d) : <StatValueSkeleton />} note={data ? `dari ${formatNumber(data.users.total)} user` : <StatNoteSkeleton />} />
            <StatCard label="Di-ban" icon="ban" value={data ? formatNumber(data.users.banned) : <StatValueSkeleton />} danger={!!data && data.users.banned > 0} note={data ? `${pct(data.users.banned, data.users.total)} dari semua user` : <StatNoteSkeleton />} />
            <StatCard label="Penyimpanan" icon="drive" value={data ? formatBytes(data.storage.r2Bytes + data.storage.syncBytes) : <StatValueSkeleton />} note={data ? "file buku + data sync" : <StatNoteSkeleton />} />
            <StatCard label="Kode undangan" icon="ticket" value={data ? formatNumber(data.invites.unused) : <StatValueSkeleton />} note={data ? "belum dipakai" : <StatNoteSkeleton />} />
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
