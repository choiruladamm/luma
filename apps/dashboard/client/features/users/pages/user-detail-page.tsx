import { useState } from "react";
import { Link, useParams } from "react-router";
import { Button, ButtonLink } from "../../../components/ui/button";
import { Skeleton } from "../../../components/ui/skeleton";
import { EmptyState, ErrorState } from "../../../components/ui/states";
import { useCopyToClipboard } from "../../../hooks/use-copy-to-clipboard";
import { ApiError } from "../../../lib/api-error";
import { toast } from "../../../stores/toast-store";
import { useOverview } from "../../overview/queries/use-overview";
import { BanDialog } from "../components/ban-dialog";
import { AiCard, SessionsCard, UsageCards } from "../components/user-detail-cards";
import { UserProfile } from "../components/user-profile";
import { useBanUser, useUnbanUser } from "../queries/use-ban-user";
import { useUserDetail } from "../queries/use-user-detail";

/** Board 05 Detail user, 06 ban confirm dialog, 07 banned. */
export function UserDetailPage() {
  const { id = "" } = useParams();
  const user = useUserDetail(id);
  const overview = useOverview();
  const ban = useBanUser();
  const unban = useUnbanUser();
  const { copy } = useCopyToClipboard();
  const [confirming, setConfirming] = useState(false);

  const doUnban = () =>
    unban.mutate(id, {
      onSuccess: () => toast(`Ban ${user.data?.email ?? "user"} dibuka`),
      onError: (e) => toast(e.message, { tone: "error" }),
    });
  const doBan = () =>
    ban.mutate(id, {
      onSuccess: () => {
        setConfirming(false);
        toast(`${user.data?.email ?? "User"} di-ban`, { action: { label: "Buka ban", onClick: doUnban } });
      },
      onError: (e) => {
        setConfirming(false);
        toast(e.message, { tone: "error" });
      },
    });

  const crumb = (
    <nav aria-label="Lokasi" className="flex items-center gap-2 text-body text-ink2">
      <Link to="/users" className="text-ink2 no-underline hover:underline">
        User
      </Link>
      <span aria-hidden="true">/</span>
      <span className="truncate font-semibold text-ink">{user.data ? user.data.name || user.data.email : "…"}</span>
    </nav>
  );

  if (user.isError) {
    const missing = user.error instanceof ApiError && user.error.code === "NOT_FOUND";
    return (
      <>
        {crumb}
        <section className="rounded-card bg-sheet">
          {missing ? (
            <EmptyState icon="user" title="User gak ditemukan" action={<ButtonLink to="/users" variant="secondary" icon="back">Ke daftar user</ButtonLink>}>
              Mungkin akunnya udah dihapus dari app.
            </EmptyState>
          ) : (
            <ErrorState message={user.error.message} onRetry={() => void user.refetch()} />
          )}
        </section>
      </>
    );
  }

  if (!user.data) {
    return (
      <>
        {crumb}
        <section aria-busy="true" aria-label="Lagi muat user" className="flex flex-col gap-6 rounded-card bg-sheet p-7">
          <div className="flex items-center gap-5">
            <Skeleton className="size-[72px]" />
            <div className="flex flex-col gap-2">
              <Skeleton className="h-6 w-64" />
              <Skeleton className="h-4 w-40" />
            </div>
          </div>
          <Skeleton className="h-12 w-full" />
        </section>
      </>
    );
  }

  const data = user.data;
  return (
    <>
      {crumb}
      <UserProfile
        user={data}
        unbanning={unban.isPending}
        onUnban={doUnban}
        onCopyEmail={() =>
          copy(data.email).then(
            () => toast("Email disalin"),
            () => toast("Gagal nyalin email. Coba lagi.", { tone: "error" }),
          )
        }
      />
      <div className="flex flex-wrap gap-4">
        <UsageCards user={data} totalR2={overview.data?.storage.r2Bytes} />
        <AiCard ai={data.ai} />
      </div>
      <SessionsCard sessions={data.sessions} />
      {!data.banned && (
        <section aria-labelledby="h-ban" className="flex flex-wrap items-center justify-between gap-4 rounded-card bg-sheet p-6">
          <div className="flex max-w-[640px] flex-col gap-1">
            <h2 id="h-ban" className="m-0 text-card font-semibold">
              Ban user ini
            </h2>
            <span className="text-body text-ink2">Kuota AI gratisnya dicabut, key yang udah ada langsung mati. Masuk, backup, dan sync tetap jalan. Bisa dibuka kapan aja dari halaman ini.</span>
          </div>
          <Button variant="danger-soft" icon="ban" onClick={() => setConfirming(true)}>
            Ban user
          </Button>
        </section>
      )}
      <BanDialog user={data} open={confirming} onClose={() => setConfirming(false)} onConfirm={doBan} pending={ban.isPending} />
    </>
  );
}
