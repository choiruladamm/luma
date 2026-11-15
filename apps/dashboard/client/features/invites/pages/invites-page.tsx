import { useMemo, useState } from "react";
import { PageHeader } from "../../../components/layout/page-header";
import { UpdatedAt } from "../../../components/layout/updated-at";
import { Button, IconButton } from "../../../components/ui/button";
import { DataTable, LoadMore } from "../../../components/ui/data-table";
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
 * Board 08 Undangan + 09 new code. One request loads every code (the API caps at 500); the
 * filter counts and "Muat lagi" work on that list, so switching filters costs nothing.
 */
export function InvitesPage() {
  const invites = useInvites();
  const create = useCreateInvites();
  const remove = useDeleteInvite();
  const { copied, copy } = useCopyToClipboard();
  const [filter, setFilter] = useState<Filter>("all");
  const [limit, setLimit] = useState(PAGE);
  const [created, setCreated] = useState<{ code: string; at: string } | null>(null);
  const [deleting, setDeleting] = useState<string | null>(null);
  const i18n = useI18n();
  const { t } = i18n;

  const all = invites.data?.items;
  const counts = useMemo(() => ({ all: all?.length ?? 0, unused: all?.filter((i) => !i.usedAt).length ?? 0, used: all?.filter((i) => i.usedAt).length ?? 0 }), [all]);
  const filtered = useMemo(() => (all ?? []).filter((i) => filter === "all" || (filter === "used") === (i.usedAt !== null)), [all, filter]);
  const rows = useMemo(() => filtered.slice(0, limit), [filtered, limit]);

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
        actions={
          <>
            <UpdatedAt at={invites.dataUpdatedAt} onRefresh={() => void invites.refetch()} refreshing={invites.isFetching} />
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
              setLimit(PAGE);
            }}
            options={(["all", "unused", "used"] as const).map((value) => ({
              value,
              label: t.invites[value],
              count: all ? counts[value] : <Skeleton className="inline-block h-3 w-4 align-middle" />,
            }))}
            className="max-w-full overflow-x-auto"
          />
          <span className="text-caption text-ink2">{t.invites.oneEach}</span>
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
          <EmptyState icon="ticket" title={filter === "unused" ? t.invites.allUsed : t.invites.noneUsed} />
        ) : (
          <DataTable
            label={t.invites.table}
            columns={columns}
            data={rows}
            minWidth={760}
            renderCard={(i) => <InviteCard invite={i} actions={actions(i)} />}
            footer={<LoadMore shown={rows.length} total={filtered.length} onMore={rows.length < filtered.length ? () => setLimit((l) => l + PAGE) : undefined} />}
          />
        )}
      </section>
      <NewInviteDialog code={created?.code ?? null} createdAt={created?.at ?? new Date().toISOString()} copied={created !== null && copied === created.code} onCopy={() => created && void copyCode(created.code)} onClose={() => setCreated(null)} />
      <DeleteInviteDialog code={deleting} onClose={() => setDeleting(null)} onConfirm={confirmDelete} pending={remove.isPending} />
    </>
  );
}
