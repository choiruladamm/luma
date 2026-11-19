import { useEffect, useId, useMemo } from "react";
import { PageHeader } from "../../../components/layout/page-header";
import { UpdatedAt } from "../../../components/layout/updated-at";
import { Button, ButtonLink } from "../../../components/ui/button";
import { Chip } from "../../../components/ui/chip";
import { DataTable, type TableSort } from "../../../components/ui/data-table";
import { Pagination } from "../../../components/ui/pagination";
import { SearchInput } from "../../../components/ui/search-input";
import { Skeleton } from "../../../components/ui/skeleton";
import { EmptyState, ErrorState } from "../../../components/ui/states";
import { useI18n } from "../../../i18n";
import { errorText } from "../../../lib/api-error";
import { formatNumber } from "../../../lib/format";
import { useOverview } from "../../overview/queries/use-overview";
import { USER_NUMERIC, UserCard, userColumns } from "../components/user-columns";
import { UsersTableSkeleton } from "../components/users-table-skeleton";
import {
  ActiveFilters,
  CLEARED_FILTERS,
  UsersFilterChips,
  UsersFilterSheet,
} from "../components/users-filters";
import { useUserSearch } from "../hooks/use-user-search";
import { activeFilterCount, type UserSort, useUsersParams } from "../hooks/use-users-params";
import { useUsers } from "../queries/use-users";

// Table column id ↔ worker sort key.
const SORT_OF: Record<string, UserSort> = {
  createdAt: "created",
  lastActiveAt: "lastActive",
  r2Bytes: "r2",
  syncBytes: "sync",
};
const COLUMN_OF: Partial<Record<UserSort, string>> = {
  created: "createdAt",
  lastActive: "lastActiveAt",
  r2: "r2Bytes",
  sync: "syncBytes",
};

/** No rows: filters win over the search, which wins over "no users yet". */
function UsersEmpty({
  filtered,
  q,
  onReset,
}: {
  filtered: boolean;
  q: string;
  onReset: () => void;
}) {
  const { t } = useI18n();
  if (filtered) {
    return (
      <EmptyState
        icon="filter"
        title={t.users.noFilterMatch}
        action={
          <Button variant="secondary" onClick={onReset}>
            {t.users.reset}
          </Button>
        }
      >
        {t.users.noFilterMatchBody}
      </EmptyState>
    );
  }
  if (q) {
    return (
      <EmptyState icon="search" title={t.users.noMatch(q)}>
        {t.users.noMatchBody}
      </EmptyState>
    );
  }
  return (
    <EmptyState
      icon="users"
      title={t.users.empty}
      action={
        <ButtonLink to="/invites" variant="secondary" icon="ticket">
          {t.users.toInvites}
        </ButtonLink>
      }
    >
      {t.users.emptyBody}
    </EmptyState>
  );
}

/**
 * Board 02 User (+ 13 loading, empty and search-empty states from design component 2), with filters,
 * column sorting, and page numbers; all of it lives in the URL (useUsersParams).
 */
export function UsersPage() {
  const { form, q, clear, invalid } = useUserSearch();
  const { params, set } = useUsersParams();
  const users = useUsers(params);
  const overview = useOverview();
  const i18n = useI18n();
  const { t, locale } = i18n;
  const columns = useMemo(() => userColumns(i18n, q), [i18n, q]);
  const rows = users.data?.items ?? [];
  // Placeholder data is the previous query's page count, not this one's.
  const pageCount = users.isPlaceholderData ? undefined : users.data?.pageCount;
  const filtered = activeFilterCount(params) > 0;
  const defaultSort: UserSort = q ? "relevance" : "created";
  const currentSort: UserSort =
    params.sort && (params.sort !== "relevance" || q) ? params.sort : defaultSort;
  const tableSort: TableSort | null = COLUMN_OF[currentSort]
    ? { id: COLUMN_OF[currentSort], dir: params.dir }
    : null;
  // Same column flips the direction; a new column starts descending (biggest / newest first).
  const onSort = (id: string) => {
    const next = SORT_OF[id]!;
    set({ sort: next, dir: next === currentSort && params.dir === "desc" ? "asc" : "desc" });
  };

  // A page past the end (rows deleted, a stale link) lands on the last page instead.
  useEffect(() => {
    if (pageCount !== undefined && params.page > pageCount) set({ page: pageCount });
  }, [pageCount, params.page, set]);
  const total = overview.data?.users.total;
  const value = form.watch("q");
  const errorId = useId();

  const renderTable = () => {
    if (users.isError && !users.data) {
      return (
        <ErrorState message={errorText(users.error, t)} onRetry={() => void users.refetch()} />
      );
    }
    if (!users.data) return <UsersTableSkeleton />;
    if (rows.length === 0) {
      return <UsersEmpty filtered={filtered} q={q} onReset={() => set(CLEARED_FILTERS)} />;
    }
    return (
      <DataTable
        label={t.users.list}
        columns={columns}
        data={rows}
        rowHref={(u) => `/users/${u.id}`}
        numeric={USER_NUMERIC}
        sort={tableSort}
        sortable={Object.keys(SORT_OF)}
        onSort={onSort}
        renderCard={(u) => <UserCard user={u} q={q} />}
        footer={
          <Pagination
            page={params.page}
            pageCount={users.data.pageCount}
            total={users.data.total}
            pageSize={params.limit}
            onPage={(page) => set({ page })}
            pageSizes={[25, 50]}
            onPageSize={(limit) => set({ limit })}
          />
        }
      />
    );
  };

  return (
    <>
      <PageHeader
        title={t.shell.users}
        after={
          total !== undefined ? (
            <Chip tone="sheet">{formatNumber(total, locale)}</Chip>
          ) : (
            <Skeleton className="h-7 w-10" />
          )
        }
        meta={
          <UpdatedAt
            at={users.dataUpdatedAt}
            onRefresh={() => void users.refetch()}
            refreshing={users.isFetching}
          />
        }
      />
      <section aria-label={t.users.list} className="scroll-mt-24 rounded-card bg-sheet">
        <div className="flex flex-col gap-3 px-6 py-5">
          {/* Phone: search + filter icon on one row; desktop: search, then the filter chips. */}
          <div className="flex items-start gap-2 md:gap-3">
            <form
              role="search"
              onSubmit={(e) => e.preventDefault()}
              className="flex min-w-0 flex-1 flex-col gap-1 md:max-w-[420px] md:flex-[1_1_280px]"
            >
              <SearchInput
                label={t.users.search}
                placeholder={t.shell.searchUsersPlaceholder}
                tone="canvas"
                onClear={clear}
                value={value}
                {...form.register("q")}
                aria-invalid={invalid || undefined}
                aria-describedby={invalid ? errorId : undefined}
              />
              {/* Always mounted, so screen readers announce the message when it appears. */}
              <span
                id={errorId}
                role="status"
                className="pl-4 text-caption text-danger-ink empty:hidden"
              >
                {invalid ? t.users.searchTooLong : ""}
              </span>
            </form>
            <UsersFilterSheet params={params} set={set} currentSort={currentSort} />
            <div className="ml-auto max-md:hidden">
              <UsersFilterChips params={params} set={set} currentSort={currentSort} />
            </div>
          </div>
          <ActiveFilters params={params} set={set} />
          <span className="flex flex-wrap items-center gap-x-5 gap-y-1 text-caption text-ink2">
            {overview.data ? (
              <span>
                {t.users.summary(
                  formatNumber(overview.data.users.total, locale),
                  formatNumber(overview.data.users.banned, locale),
                  overview.data.users.total,
                )}
              </span>
            ) : (
              <span aria-hidden="true" className="flex items-center gap-5">
                <Skeleton className="h-3 w-[72px]" />
                <Skeleton className="h-3 w-14" />
              </span>
            )}
          </span>
        </div>
        {/* Clip only the table to the card corners: the toolbar menus must overflow below it. */}
        <div className="overflow-hidden rounded-b-card">{renderTable()}</div>
      </section>
    </>
  );
}
