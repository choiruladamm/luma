import { useMemo, useState } from "react";
import { PageHeader } from "../../../components/layout/page-header";
import { UpdatedAt } from "../../../components/layout/updated-at";
import { Button, IconButton } from "../../../components/ui/button";
import { DataTable, type TableSort } from "../../../components/ui/data-table";
import { Pagination } from "../../../components/ui/pagination";
import { SearchInput } from "../../../components/ui/search-input";
import { Segmented } from "../../../components/ui/segmented";
import { Skeleton } from "../../../components/ui/skeleton";
import { EmptyState, ErrorState } from "../../../components/ui/states";
import { useCopyToClipboard } from "../../../hooks/use-copy-to-clipboard";
import { getI18n, useI18n } from "../../../i18n";
import { errorText } from "../../../lib/api-error";
import { toast } from "../../../stores/toast-store";
import type { InviteItem } from "../api/invites-api";
import { DeleteInviteDialog } from "../components/delete-invite-dialog";
import { InvitesTableSkeleton } from "../components/invites-table-skeleton";
import { InviteCard, inviteColumns } from "../components/invite-columns";
import { NewInviteDialog } from "../components/new-invite-dialog";
import { useCreateInvites, useDeleteInvite, useInvites } from "../queries/use-invites";

type Filter = "all" | "unused" | "used";
const PAGE = 20;

/**
 * Board 08 Undangan + 09 new code. One request loads every code (the API caps at 500); search,
 * filter counts, sorting, and pages all work on that list, so none of them costs a request.
 */
export function InvitesPage() {
  const invites = useInvites();
  const create = useCreateInvites();
  const remove = useDeleteInvite();
  const { copied, copy } = useCopyToClipboard();
  const [filter, setFilter] = useState<Filter>("all");
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState("");
  const [sort, setSort] = useState<TableSort | null>(null);
  const [created, setCreated] = useState<{ code: string; at: string } | null>(null);
  const [deleting, setDeleting] = useState<string | null>(null);
  const i18n = useI18n();
  const { t } = i18n;

  const all = invites.data?.items;
  const counts = useMemo(() => ({ all: all?.length ?? 0, unused: all?.filter((i) => !i.usedAt).length ?? 0, used: all?.filter((i) => i.usedAt).length ?? 0 }), [all]);
  const needle = search.trim().toLowerCase();
  const filtered = useMemo(() => {
    const list = (all ?? []).filter(
      (i) =>
        (filter === "all" || (filter === "used") === (i.usedAt !== null)) &&
        // Codes are shown with dashes; match with or without them.
        (!needle || i.code.toLowerCase().replaceAll("-", "").includes(needle.replaceAll("-", "")) || (i.usedBy?.email.toLowerCase().includes(needle) ?? false)),
    );
    if (!sort) return list; // API order: unused first, then the most recently used
    const key = (i: InviteItem) => (sort.id === "code" ? i.code : (i.usedAt ?? ""));
    const sign = sort.dir === "asc" ? 1 : -1;
    return [...list].sort((a, b) => sign * key(a).localeCompare(key(b)));
  }, [all, filter, needle, sort]);
  const pageCount = Math.max(1, Math.ceil(filtered.length / PAGE));
  const current = Math.min(page, pageCount);
  const rows = useMemo(() => filtered.slice((current - 1) * PAGE, current * PAGE), [filtered, current]);
  const onSort = (id: string) => {
    setSort((s) => ({ id, dir: s?.id === id && s.dir === "desc" ? "asc" : "desc" }));
    setPage(1);
  };

  const copyCode = (code: string) =>
    copy(code).then(
      () => toast(getI18n().t.invites.copied(code)),
      () => toast(getI18n().t.invites.copyFailed, { tone: "error" }),
    );
  const makeCode = () =>
    create.mutate(1, {
      onSuccess: (res) => setCreated({ code: res.codes[0]!, at: new Date().toISOString() }),
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
        meta={<UpdatedAt at={invites.dataUpdatedAt} onRefresh={() => void invites.refetch()} refreshing={invites.isFetching} />}
        actions={
          <>
            <Button variant="primary" icon="plus" onClick={makeCode} loading={create.isPending}>
              {t.invites.create}
            </Button>
          </>
        }
      />
      <section aria-label={t.invites.list} className="overflow-hidden rounded-card bg-sheet">
        <div className="flex flex-wrap items-center justify-between gap-3 px-6 py-5">
          <Segmented
            label={t.invites.filter}
            value={filter}
            onChange={(f) => {
              setFilter(f);
              setPage(1);
            }}
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
              count: all ? counts[value] : <Skeleton className="inline-block h-3 w-4 align-middle" />,
            }))}
            className="max-w-full"
          />
          <SearchInput
            label={t.invites.search}
            placeholder={`${t.invites.search}…`}
            tone="canvas"
            className="min-w-0 flex-[1_1_240px] md:max-w-[320px]"
            value={search}
            onChange={(e) => {
              setSearch(e.target.value);
              setPage(1);
            }}
            onClear={() => setSearch("")}
          />
          <span className="basis-full text-caption text-ink2">{t.invites.oneEach}</span>
        </div>
        {invites.isError ? (
          <ErrorState message={errorText(invites.error, t)} onRetry={() => void invites.refetch()} />
        ) : !all ? (
          <InvitesTableSkeleton />
        ) : all.length === 0 ? (
          <EmptyState icon="ticket" title={t.invites.empty} action={<Button variant="primary" icon="plus" onClick={makeCode}>{t.invites.create}</Button>}>
            {t.invites.emptyBody}
          </EmptyState>
        ) : filtered.length === 0 ? (
          needle ? (
            <EmptyState icon="search" title={t.invites.noSearchMatch(search.trim())} />
          ) : (
            <EmptyState icon="ticket" title={filter === "unused" ? t.invites.allUsed : t.invites.noneUsed} />
          )
        ) : (
          <DataTable
            label={t.invites.table}
            columns={columns}
            data={rows}
            minWidth={760}
            sort={sort}
            sortable={["code", "usedAt"]}
            onSort={onSort}
            renderCard={(i) => <InviteCard invite={i} actions={actions(i)} />}
            footer={<Pagination page={current} pageCount={pageCount} total={filtered.length} pageSize={PAGE} onPage={setPage} />}
          />
        )}
      </section>
      <NewInviteDialog code={created?.code ?? null} createdAt={created?.at ?? new Date().toISOString()} copied={created !== null && copied === created.code} onCopy={() => created && void copyCode(created.code)} onClose={() => setCreated(null)} />
      <DeleteInviteDialog code={deleting} onClose={() => setDeleting(null)} onConfirm={confirmDelete} pending={remove.isPending} />
    </>
  );
}
