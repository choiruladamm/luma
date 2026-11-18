import { useEffect, useMemo, useState } from "react";
import { PageHeader } from "../../../components/layout/page-header";
import { UpdatedAt } from "../../../components/layout/updated-at";
import { Button, IconButton } from "../../../components/ui/button";
import { DataTable, type TableSort } from "../../../components/ui/data-table";
import { Pagination } from "../../../components/ui/pagination";
import { SearchInput } from "../../../components/ui/search-input";
import { Segmented } from "../../../components/ui/segmented";
import { Select } from "../../../components/ui/select";
import { Skeleton } from "../../../components/ui/skeleton";
import { EmptyState, ErrorState } from "../../../components/ui/states";
import { useCopyToClipboard } from "../../../hooks/use-copy-to-clipboard";
import { useSlidingPill } from "../../../hooks/use-sliding-pill";
import { useDebounce } from "../../../hooks/use-debounce";
import { getI18n, useI18n } from "../../../i18n";
import { errorText } from "../../../lib/api-error";
import { cn } from "../../../lib/cn";
import { toast } from "../../../stores/toast-store";
import type { InviteItem } from "../api/invites-api";
import { type InviteSort, type InvitesParams, useInvitesParams } from "../hooks/use-invites-params";
import { DeleteInviteDialog } from "../components/delete-invite-dialog";
import { InvitesTableSkeleton } from "../components/invites-table-skeleton";
import { InviteCard, inviteColumns } from "../components/invite-columns";
import { NewInviteDialog } from "../components/new-invite-dialog";
import { useCreateInvites, useDeleteInvite, useInvites } from "../queries/use-invites";

type Filter = "all" | "unused" | "used";

/** Desktop status tabs: label + count, an ink underline that slides to the active tab. */
function StatusTabs({ value, counts, onChange }: { value: Filter; counts?: Record<Filter, number>; onChange: (f: Filter) => void }) {
  const { t } = useI18n();
  const tabs: Filter[] = ["all", "unused", "used"];
  const pill = useSlidingPill(tabs.indexOf(value), tabs.length);
  return (
    <div role="tablist" aria-label={t.invites.filter} onMouseLeave={pill.onMouseLeave} className="relative flex gap-1 border-b border-track px-4 max-md:hidden">
      <span aria-hidden="true" style={pill.activeStyle} className={cn("absolute bottom-[-1px] left-0 h-0.5 rounded-full bg-ink", pill.slide, pill.activeVisible ? "opacity-100" : "opacity-0")} />
      {tabs.map((tab, i) => (
        <button
          key={tab}
          {...pill.item(i)}
          type="button"
          role="tab"
          aria-selected={tab === value}
          onClick={() => onChange(tab)}
          className={cn("inline-flex h-12 items-center gap-2 rounded-t-[12px] px-3 text-body transition-colors hover:bg-muted/60", tab === value ? "font-semibold text-ink" : "font-medium text-ink2")}
        >
          {tab === "all" ? t.invites.all : t.invites[tab]}
          <span className={cn("rounded-full px-2 text-chip leading-5 tabular-nums", tab === value ? "bg-ink text-canvas" : "bg-muted text-ink2")}>
            {counts ? counts[tab] : <Skeleton className="inline-block h-3 w-4 align-middle" />}
          </span>
        </button>
      ))}
    </div>
  );
}

/**
 * Board 08 (Undangan, Invites) + 09 new code. Search, status tabs (with counts), "used within", sort, and
 * pages run on the worker (1 batch per change); all of it lives in the URL (useInvitesParams).
 */
export function InvitesPage() {
  const { params, set } = useInvitesParams();
  const invites = useInvites(params);
  const create = useCreateInvites();
  const remove = useDeleteInvite();
  const { copied, copy } = useCopyToClipboard();
  const [created, setCreated] = useState<{ code: string; at: string } | null>(null);
  const [deleting, setDeleting] = useState<string | null>(null);
  const i18n = useI18n();
  const { t } = i18n;

  // The field updates at once; the URL (and the request) only after a 300ms pause.
  const [search, setSearch] = useState(params.q);
  const settled = useDebounce(search.trim(), 300);
  useEffect(() => {
    if (settled !== params.q) set({ q: settled });
  }, [settled]);

  const data = invites.data;
  const rows = data?.items ?? [];
  const counts = data?.counts;
  const filter: Filter = params.status ?? "all";
  const tableSort: TableSort | null = params.sort === "default" ? null : { id: params.sort, dir: params.dir };
  const onSort = (id: string) => {
    const sort = id as InviteSort;
    set({ sort, dir: params.sort === sort && params.dir === "desc" ? "asc" : "desc" });
  };
  const sortValue = `${params.sort}:${params.sort === "default" ? "desc" : params.dir}`;
  const sorts: [string, string][] = [
    ["default:desc", t.invites.sortDefault],
    ["createdAt:desc", t.invites.sortNewestCreated],
    ["createdAt:asc", t.invites.sortOldestCreated],
    ["usedAt:desc", t.invites.sortNewestUsed],
    ["usedAt:asc", t.invites.sortOldestUsed],
    ["code:asc", t.invites.sortCodeAsc],
    ["code:desc", t.invites.sortCodeDesc],
  ];

  // A page past the end (codes deleted, a stale link) lands on the last page instead.
  useEffect(() => {
    if (data && params.page > data.pageCount) set({ page: data.pageCount });
  }, [data?.pageCount, params.page]);

  const copyCode = (code: string) =>
    copy(code).then(
      () => toast(getI18n().t.invites.copied(code)),
      () => toast(getI18n().t.invites.copyFailed, { tone: "error" }),
    );
  const makeCode = () =>
    create.mutate(1, {
      onSuccess: (res) => setCreated({ code: res.codes[0]!, at: res.createdAt }),
      onError: (e) => toast(errorText(e, getI18n().t), { tone: "error" }),
    });
  const confirmDelete = () =>
    remove.mutate(deleting!, {
      onSuccess: () => {
        toast(getI18n().t.invites.deleted(deleting!));
        setDeleting(null);
      },
      onError: (e) => {
        setDeleting(null);
        toast(errorText(e, getI18n().t), { tone: "error" });
      },
    });

  const actions = (invite: InviteItem) => (
    <span className="flex justify-end gap-1.5">
      <IconButton icon="copy" label={t.invites.copyCode(invite.code)} onClick={() => void copyCode(invite.code)} />
      {!invite.usedAt && <IconButton icon="x" label={t.invites.deleteCode(invite.code)} variant="danger-soft" onClick={() => setDeleting(invite.code)} />}
    </span>
  );
  // `actions` only closes over stable setters and the clipboard hook.
  // `actions` reads `t`, so the columns follow the language too.
  const columns = useMemo(() => inviteColumns(i18n, actions), [copy, i18n]);

  return (
    <>
      <PageHeader
        title={t.shell.invites}
        after={<span className="text-caption text-ink2 max-md:hidden">{t.invites.oneEach}</span>}
        meta={<UpdatedAt at={invites.dataUpdatedAt} onRefresh={() => void invites.refetch()} refreshing={invites.isFetching} />}
        actions={
          <>
            <Button variant="primary" icon="plus" onClick={makeCode} loading={create.isPending}>
              {t.invites.create}
            </Button>
          </>
        }
      />
      <section aria-label={t.invites.list} className="scroll-mt-24 overflow-hidden rounded-card bg-sheet">
        {/* Desktop: underline tabs across the top of the card, then search left + chips right
            (same toolbar as Users). Phone: search, chips, then the segmented tabs. */}
        <StatusTabs value={filter} counts={counts} onChange={(f) => set({ status: f === "all" ? undefined : f })} />
        <div className="flex flex-col gap-3 px-6 py-5 md:flex-row md:items-center">
          <div className="min-w-0 md:max-w-[420px] md:flex-1">
            <SearchInput label={t.invites.search} placeholder={`${t.invites.search}…`} tone="canvas" className="w-full" value={search} onChange={(e) => setSearch(e.target.value)} onClear={() => setSearch("")} />
          </div>
          <div className="md:ml-auto">
            {/* Phone: the two chips split the row; desktop: right of the search. */}
            <div className="grid w-full grid-cols-2 gap-2 md:ml-auto md:flex md:w-auto md:items-center [&>*]:min-w-0 max-md:[&_button]:w-full">
              <Select
                label={t.invites.usedWithin}
                shortLabel={t.invites.usedWithinShort}
                value={params.usedWithin ?? ""}
                options={[["", t.invites.anyTime], ["7d", t.invites.within7d], ["30d", t.invites.within30d]]}
                active={!!params.usedWithin}
                onChange={(v) => set({ usedWithin: (v || undefined) as InvitesParams["usedWithin"] })}
              />
              <Select
                label={t.users.sortLabel}
                shortLabel=""
                value={sortValue}
                options={sorts}
                active={params.sort !== "default"}
                onChange={(v) => {
                  const [sort, dir] = v.split(":") as [InviteSort, "asc" | "desc"];
                  set({ sort, dir });
                }}
              />
            </div>
          </div>
          <div className="md:hidden">
            <Segmented
              label={t.invites.filter}
              value={filter}
              onChange={(f) => set({ status: f === "all" ? undefined : f })}
              stretch="phone"
              options={(["all", "unused", "used"] as const).map((value) => ({
                value,
                // Phones show the short word; the full label stays the accessible name.
                label:
                  value === "all" ? (
                    t.invites.all
                  ) : (
                    <>
                      <span aria-hidden="true" className="md:hidden">
                        {value === "unused" ? t.invites.unusedShort : t.invites.usedShort}
                      </span>
                      <span className="max-md:sr-only">{t.invites[value]}</span>
                    </>
                  ),
                count: counts ? counts[value] : <Skeleton className="inline-block h-3 w-4 align-middle" />,
              }))}
              className="max-w-full"
            />
          </div>
        </div>
        {invites.isError ? (
          <ErrorState message={errorText(invites.error, t)} onRetry={() => void invites.refetch()} />
        ) : !data ? (
          <InvitesTableSkeleton />
        ) : rows.length === 0 ? (
          counts?.all === 0 && !params.q ? (
            <EmptyState icon="ticket" title={t.invites.empty} action={<Button variant="primary" icon="plus" onClick={makeCode}>{t.invites.create}</Button>}>
              {t.invites.emptyBody}
            </EmptyState>
          ) : params.q && counts?.all === 0 ? (
            <EmptyState icon="search" title={t.invites.noSearchMatch(params.q)} />
          ) : (
            <EmptyState icon="ticket" title={params.usedWithin ? t.invites.noneUsedWithin : filter === "unused" ? t.invites.allUsed : t.invites.noneUsed} />
          )
        ) : (
          <DataTable
            label={t.invites.table}
            columns={columns}
            data={rows}
            minWidth={880}
            sort={tableSort}
            sortable={["code", "createdAt", "usedAt"]}
            onSort={onSort}
            renderCard={(i) => <InviteCard invite={i} actions={actions(i)} />}
            footer={<Pagination page={params.page} pageCount={data.pageCount} total={data.total} pageSize={params.limit} onPage={(page) => set({ page })} pageSizes={[20, 50]} onPageSize={(limit) => set({ limit: limit as 20 | 50 })} />}
          />
        )}
      </section>
      <NewInviteDialog code={created?.code ?? null} createdAt={created?.at ?? new Date().toISOString()} copied={created !== null && copied === created.code} onCopy={() => created && void copyCode(created.code)} onClose={() => setCreated(null)} />
      <DeleteInviteDialog code={deleting} onClose={() => setDeleting(null)} onConfirm={confirmDelete} pending={remove.isPending} />
    </>
  );
}
