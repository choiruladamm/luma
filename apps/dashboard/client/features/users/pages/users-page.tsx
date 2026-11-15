import { useMemo } from "react";
import { PageHeader } from "../../../components/layout/page-header";
import { UpdatedAt } from "../../../components/layout/updated-at";
import { ButtonLink } from "../../../components/ui/button";
import { Chip } from "../../../components/ui/chip";
import { DataTable, LoadMore } from "../../../components/ui/data-table";
import { SearchInput } from "../../../components/ui/search-input";
import { Skeleton } from "../../../components/ui/skeleton";
import { EmptyState, ErrorState } from "../../../components/ui/states";
import { useI18n } from "../../../i18n";
import { errorText } from "../../../lib/api-error";
import { formatNumber } from "../../../lib/format";
import { useOverview } from "../../overview/queries/use-overview";
import { USER_NUMERIC, UserCard, userColumns } from "../components/user-columns";
import { UsersTableSkeleton } from "../components/users-table-skeleton";
import { useUserSearch } from "../hooks/use-user-search";
import { useUsers } from "../queries/use-users";

/** Board 02 User (+ 13 loading, empty and search-empty states from komponen 2). */
export function UsersPage() {
  const { form, q, clear, invalid } = useUserSearch();
  const users = useUsers(q);
  const overview = useOverview();
  const i18n = useI18n();
  const { t, locale } = i18n;
  const columns = useMemo(() => userColumns(i18n), [i18n]);
  const rows = useMemo(() => users.data?.pages.flatMap((p) => p.items) ?? [], [users.data]);
  const total = overview.data?.users.total;
  const value = form.watch("q");

  return (
    <>
      <PageHeader
        title={t.shell.users}
        after={total !== undefined ? <Chip>{formatNumber(total, locale)}</Chip> : <Skeleton className="h-7 w-10" />}
        actions={<UpdatedAt at={users.dataUpdatedAt} onRefresh={() => void users.refetch()} refreshing={users.isFetching} />}
      />
      <section aria-label={t.users.list} className="overflow-hidden rounded-card bg-sheet">
        <div className="flex flex-wrap items-center justify-between gap-3 px-6 py-5">
          <form role="search" onSubmit={(e) => e.preventDefault()} className="flex min-w-0 flex-[1_1_280px] flex-col gap-1">
            <SearchInput label={t.users.search} placeholder={t.shell.searchUsersPlaceholder} tone="canvas" className="max-w-[420px]" onClear={clear} value={value} {...form.register("q")} aria-invalid={invalid || undefined} />
            {invalid && <span className="pl-4 text-caption text-danger-ink">{t.users.searchTooLong}</span>}
          </form>
          <span className="flex flex-wrap items-center gap-x-5 gap-y-1 text-caption text-ink2">
            {overview.data ? (
              <span>{t.users.summary(formatNumber(overview.data.users.total, locale), formatNumber(overview.data.users.banned, locale), overview.data.users.total)}</span>
            ) : (
              <span aria-hidden="true" className="flex items-center gap-5">
                <Skeleton className="h-3 w-[72px]" />
                <Skeleton className="h-3 w-14" />
              </span>
            )}
            <span>{t.users.sorted}</span>
          </span>
        </div>
        {users.isError ? (
          <ErrorState message={errorText(users.error, t)} onRetry={() => void users.refetch()} />
        ) : !users.data ? (
          <UsersTableSkeleton />
        ) : rows.length === 0 ? (
          q ? (
            <EmptyState icon="search" title={t.users.noMatch(q)}>
              {t.users.noMatchBody}
            </EmptyState>
          ) : (
            <EmptyState icon="users" title={t.users.empty} action={<ButtonLink to="/invites" variant="secondary" icon="ticket">{t.users.toInvites}</ButtonLink>}>
              {t.users.emptyBody}
            </EmptyState>
          )
        ) : (
          <DataTable
            label={t.users.list}
            columns={columns}
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
