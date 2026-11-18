import { useState } from "react";
import { Link, useParams } from "react-router";
import { Button, ButtonLink } from "../../../components/ui/button";
import { EmptyState, ErrorState } from "../../../components/ui/states";
import { useCopyToClipboard } from "../../../hooks/use-copy-to-clipboard";
import { getI18n, useI18n } from "../../../i18n";
import { ApiError, errorText } from "../../../lib/api-error";
import { toast } from "../../../stores/toast-store";
import { useOverview } from "../../overview/queries/use-overview";
import { BanDialog } from "../components/ban-dialog";
import { AiCard, NUMBER_GRID, SessionsCard, UsageCards } from "../components/user-detail-cards";
import { UserDetailSkeleton } from "../components/user-detail-skeleton";
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
  const { t } = useI18n();

  const doUnban = () =>
    unban.mutate(id, {
      onSuccess: () => {
        // getI18n, not the render's `t`: the admin may switch language while the request runs.
        const { t } = getI18n();
        toast(t.userDetail.unbanned(user.data?.email ?? t.userDetail.someone));
      },
      onError: (e) => toast(errorText(e, getI18n().t), { tone: "error" }),
    });
  const doBan = () =>
    ban.mutate(id, {
      onSuccess: () => {
        setConfirming(false);
        const { t } = getI18n();
        toast(t.userDetail.bannedToast(user.data?.email ?? t.userDetail.someone), {
          action: { label: t.userDetail.unban, onClick: doUnban },
        });
      },
      onError: (e) => {
        setConfirming(false);
        toast(errorText(e, getI18n().t), { tone: "error" });
      },
    });

  const crumb = (
    <nav
      aria-label={t.userDetail.breadcrumb}
      className="flex items-center gap-2 text-body text-ink2"
    >
      <Link to="/users" className="text-ink2 no-underline hover:underline">
        {t.shell.users}
      </Link>
      <span aria-hidden="true">/</span>
      <span className="truncate font-semibold text-ink">
        {user.data ? user.data.name || user.data.email : "…"}
      </span>
    </nav>
  );

  if (user.isError) {
    const missing = user.error instanceof ApiError && user.error.code === "NOT_FOUND";
    return (
      <>
        {crumb}
        <section className="rounded-card bg-sheet">
          {missing ? (
            <EmptyState
              icon="user"
              title={t.userDetail.notFound}
              action={
                <ButtonLink to="/users" variant="secondary" icon="back">
                  {t.userDetail.backToList}
                </ButtonLink>
              }
            >
              {t.userDetail.notFoundBody}
            </EmptyState>
          ) : (
            <ErrorState message={errorText(user.error, t)} onRetry={() => void user.refetch()} />
          )}
        </section>
      </>
    );
  }

  if (!user.data) {
    return (
      <>
        {crumb}
        <UserDetailSkeleton />
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
            () => toast(getI18n().t.userDetail.emailCopied),
            () => toast(getI18n().t.userDetail.emailCopyFailed, { tone: "error" }),
          )
        }
      />
      <div className={NUMBER_GRID}>
        <UsageCards user={data} totalR2={overview.data?.storage.r2Bytes} />
        <AiCard ai={data.ai} />
      </div>
      <SessionsCard sessions={data.sessions} />
      {!data.banned && (
        <section
          aria-labelledby="h-ban"
          className="flex flex-wrap items-center justify-between gap-4 rounded-card bg-sheet p-6"
        >
          <div className="flex max-w-[640px] flex-col gap-1">
            <h2 id="h-ban" className="m-0 text-card font-semibold">
              {t.userDetail.banTitle}
            </h2>
            <span className="text-body text-ink2">{t.userDetail.banBody}</span>
          </div>
          <Button variant="danger-soft" icon="ban" onClick={() => setConfirming(true)}>
            {t.userDetail.ban}
          </Button>
        </section>
      )}
      <BanDialog
        user={data}
        open={confirming}
        onClose={() => setConfirming(false)}
        onConfirm={doBan}
        pending={ban.isPending}
      />
    </>
  );
}
