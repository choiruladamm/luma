import { useMemo } from "react";
import { PageHeader } from "../../../components/layout/page-header";
import { UpdatedAt } from "../../../components/layout/updated-at";
import { ButtonLink } from "../../../components/ui/button";
import { Chip } from "../../../components/ui/chip";
import { DataTable, LoadMore } from "../../../components/ui/data-table";
import { SearchInput } from "../../../components/ui/search-input";
import { EmptyState, ErrorState } from "../../../components/ui/states";
import { formatNumber } from "../../../lib/format";
import { useOverview } from "../../overview/queries/use-overview";
import { USER_NUMERIC, UserCard, userColumns } from "../components/user-columns";
import { UsersTableSkeleton } from "../components/users-table-skeleton";
import { useUserSearch } from "../hooks/use-user-search";
import { useUsers } from "../queries/use-users";

/** Board 02 User (+ 13 loading, empty and search-empty states from komponen 2). */
export function UsersPage() {
  const { form, q, clear, error } = useUserSearch();
  const users = useUsers(q);
  const overview = useOverview();
  const rows = useMemo(() => users.data?.pages.flatMap((p) => p.items) ?? [], [users.data]);
  const total = overview.data?.users.total;
  const value = form.watch("q");

  return (
    <>
      <PageHeader
        title="User"
        after={total !== undefined && <Chip>{formatNumber(total)}</Chip>}
        actions={<UpdatedAt at={users.dataUpdatedAt} onRefresh={() => void users.refetch()} refreshing={users.isFetching} />}
      />
      <section aria-label="Daftar user" className="overflow-hidden rounded-card bg-sheet">
        <div className="flex flex-wrap items-center justify-between gap-3 px-6 py-5">
          <form role="search" onSubmit={(e) => e.preventDefault()} className="flex min-w-0 flex-[1_1_280px] flex-col gap-1">
            <SearchInput label="Cari email" placeholder="Cari email user…" tone="canvas" className="max-w-[420px]" onClear={clear} value={value} {...form.register("q")} aria-invalid={error ? true : undefined} />
            {error && <span className="pl-4 text-caption text-danger-ink">{error}</span>}
          </form>
          <span className="text-caption text-ink2">
            {total !== undefined && `${formatNumber(total)} user · ${formatNumber(overview.data!.users.banned)} di-ban · `}Urut dari yang paling baru daftar
          </span>
        </div>
        {users.isError ? (
          <ErrorState message={users.error.message} onRetry={() => void users.refetch()} />
        ) : !users.data ? (
          <UsersTableSkeleton />
        ) : rows.length === 0 ? (
          q ? (
            <EmptyState icon="search" title={`Gak ada email yang cocok sama “${q}”`}>
              Cek ejaannya, atau cari pakai sebagian email aja.
            </EmptyState>
          ) : (
            <EmptyState icon="users" title="Belum ada user" action={<ButtonLink to="/invites" variant="secondary" icon="ticket">Ke Undangan</ButtonLink>}>
              Selama beta, user baru masuk lewat kode undangan. Begitu ada yang daftar, mereka muncul di sini.
            </EmptyState>
          )
        ) : (
          <DataTable
            label="Daftar user"
            columns={userColumns}
            data={rows}
            rowHref={(u) => `/users/${u.id}`}
            numeric={USER_NUMERIC}
            sortedBy="createdAt"
            renderCard={(u) => <UserCard user={u} />}
            footer={<LoadMore shown={rows.length} total={q ? undefined : total} onMore={users.hasNextPage ? () => void users.fetchNextPage() : undefined} loading={users.isFetchingNextPage} />}
          />
        )}
      </section>
    </>
  );
}
