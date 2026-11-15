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
      () => toast(`Kode ${code} disalin`),
      () => toast("Gagal nyalin kode. Coba lagi.", { tone: "error" }),
    );
  const makeCode = () =>
    create.mutate(1, {
      onSuccess: (res) => setCreated({ code: res.codes[0]!, at: new Date().toISOString() }),
      onError: (e) => toast(errorText(e, getI18n().t), { tone: "error" }),
    });
  const confirmDelete = () =>
    remove.mutate(deleting!, {
      onSuccess: () => {
        toast(`Kode ${deleting} dihapus`);
        setDeleting(null);
      },
      onError: (e) => {
        setDeleting(null);
        toast(errorText(e, getI18n().t), { tone: "error" });
      },
    });

  const actions = (invite: InviteItem) => (
    <span className="flex justify-end gap-1.5">
      <IconButton icon="copy" label={`Salin ${invite.code}`} onClick={() => void copyCode(invite.code)} />
      {!invite.usedAt && <IconButton icon="x" label={`Hapus ${invite.code}`} variant="danger-soft" onClick={() => setDeleting(invite.code)} />}
    </span>
  );
  // `actions` only closes over stable setters and the clipboard hook.
  const columns = useMemo(() => inviteColumns(i18n, actions), [copy, i18n]);

  return (
    <>
      <PageHeader
        title="Undangan"
        actions={
          <>
            <UpdatedAt at={invites.dataUpdatedAt} onRefresh={() => void invites.refetch()} refreshing={invites.isFetching} />
            <Button variant="primary" icon="plus" onClick={makeCode} disabled={create.isPending}>
              {create.isPending ? "Lagi bikin…" : "Bikin kode"}
            </Button>
          </>
        }
      />
      <section aria-label="Daftar kode undangan" className="overflow-hidden rounded-card bg-sheet">
        <div className="flex flex-wrap items-center justify-between gap-3 px-6 py-5">
          <Segmented
            label="Saring kode"
            value={filter}
            onChange={(f) => {
              setFilter(f);
              setLimit(PAGE);
            }}
            options={[
              { value: "all", label: "Semua", count: counts.all },
              { value: "unused", label: "Belum dipakai", count: counts.unused },
              { value: "used", label: "Udah dipakai", count: counts.used },
            ]}
            className="max-w-full overflow-x-auto"
          />
          <span className="text-caption text-ink2">Satu kode buat satu akun</span>
        </div>
        {invites.isError ? (
          <ErrorState message={errorText(invites.error, t)} onRetry={() => void invites.refetch()} />
        ) : !all ? (
          <div aria-busy="true" aria-label="Lagi muat kode undangan" className="flex flex-col gap-4 px-6 pb-6">
            {Array.from({ length: 5 }, (_, i) => (
              <Skeleton key={i} className="h-5 w-full" />
            ))}
          </div>
        ) : all.length === 0 ? (
          <EmptyState icon="ticket" title="Belum ada kode undangan" action={<Button variant="primary" icon="plus" onClick={makeCode}>Bikin kode</Button>}>
            Bikin satu buat ngajak orang ikut beta.
          </EmptyState>
        ) : filtered.length === 0 ? (
          <EmptyState icon="ticket" title={filter === "unused" ? "Semua kode udah dipakai" : "Belum ada kode yang dipakai"} />
        ) : (
          <DataTable
            label="Kode undangan"
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
