import { Link } from "react-router";
import { Avatar } from "../../../components/ui/avatar";
import { Banner } from "../../../components/ui/banner";
import { Button } from "../../../components/ui/button";
import { Chip } from "../../../components/ui/chip";
import { useI18n } from "../../../i18n";
import { formatDateTime, formatRelative } from "../../../lib/format";
import type { UserDetail } from "../api/users-api";
import { UserStatusChip } from "./user-columns";

const PROVIDERS: Record<string, string> = { google: "Google", credential: "Email" };

export const providerLabel = (ids: string[]) => (ids.length ? ids.map((id) => PROVIDERS[id] ?? id).join(", ") : "—");

/** Board 05/07: profile card; banned users get the banner on top (no ban date: not stored). */
export function UserProfile({ user, onCopyEmail, onUnban, unbanning }: { user: UserDetail; onCopyEmail: () => void; onUnban: () => void; unbanning: boolean }) {
  const i18n = useI18n();
  const { t, locale } = i18n;
  const facts: [string, React.ReactNode][] = [
    [t.users.joined, formatDateTime(user.createdAt, locale)],
    [t.users.lastActive, user.lastActiveAt ? `${formatRelative(user.lastActiveAt, i18n)} · ${formatDateTime(user.lastActiveAt, locale)}` : t.time.never],
    [t.userDetail.signsInWith, providerLabel(user.providers)],
    [
      t.userDetail.inviteCode,
      user.invite ? (
        <Link to="/invites" className="font-mono text-ink no-underline hover:underline">
          {user.invite.code}
        </Link>
      ) : (
        "—"
      ),
    ],
  ];
  return (
    <section aria-label={t.userDetail.profile} className="flex flex-col gap-6 rounded-card bg-sheet p-6 md:p-7">
      {user.banned && (
        <Banner
          title={t.userDetail.bannedBanner}
          action={
            <Button variant="sheet" icon="key" onClick={onUnban} loading={unbanning}>
              {t.userDetail.unban}
            </Button>
          }
        >
          {t.userDetail.bannedBannerBody}
        </Banner>
      )}
      <div className="flex flex-wrap items-center gap-5">
        <Avatar seed={user.email} label={user.name || user.email} size={72} />
        <div className="flex min-w-0 flex-[1_1_320px] flex-col gap-1.5">
          <h1 className="m-0 font-display text-title font-semibold [overflow-wrap:anywhere]">{user.email}</h1>
          <div className="flex flex-wrap items-center gap-2">
            {user.name && <span className="text-body text-ink2">{user.name}</span>}
            <UserStatusChip banned={user.banned} />
            {user.hasAiKey && <Chip icon="key">{t.userDetail.freeAi}</Chip>}
          </div>
        </div>
        <Button variant="secondary" icon="copy" onClick={onCopyEmail}>
          {t.userDetail.copyEmail}
        </Button>
      </div>
      <dl className="m-0 grid grid-cols-[repeat(auto-fit,minmax(180px,1fr))] gap-5 border-t border-track pt-5">
        {facts.map(([k, v]) => (
          <div key={k} className="flex flex-col gap-1">
            <dt className="text-caption font-medium text-ink2">{k}</dt>
            <dd className="m-0 text-body font-semibold tabular-nums">{v}</dd>
          </div>
        ))}
      </dl>
    </section>
  );
}
