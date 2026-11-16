import { Link } from "react-router";
import { Avatar } from "../../../components/ui/avatar";
import { Banner } from "../../../components/ui/banner";
import { Button, IconButton } from "../../../components/ui/button";
import { Chip } from "../../../components/ui/chip";
import { useI18n } from "../../../i18n";
import { formatDateTime, formatRelative } from "../../../lib/format";
import type { UserDetail } from "../api/users-api";
import { UserStatusChip } from "./user-columns";

/** Long emails wrap after the "@" first, not in the middle of a word. */
const emailParts = (email: string) => {
  const at = email.indexOf("@");
  return at < 0 ? email : (
    <>
      {email.slice(0, at)}
      <wbr />
      {email.slice(at)}
    </>
  );
};

const PROVIDERS: Record<string, string> = { google: "Google", credential: "Email" };

export const providerLabel = (ids: string[]) => (ids.length ? ids.map((id) => PROVIDERS[id] ?? id).join(", ") : "—");

/** Board 05/07: profile card; banned users get the banner on top (no ban date: not stored). */
export function UserProfile({ user, onCopyEmail, onUnban, unbanning }: { user: UserDetail; onCopyEmail: () => void; onUnban: () => void; unbanning: boolean }) {
  const i18n = useI18n();
  const { t, locale } = i18n;
  const facts: [string, React.ReactNode][] = [
    [t.users.joined, formatDateTime(user.createdAt, locale)],
    [
      t.users.lastActive,
      user.lastActiveAt ? (
        <span className="flex flex-col">
          {formatRelative(user.lastActiveAt, i18n)}
          <span className="text-caption font-normal text-ink2">{formatDateTime(user.lastActiveAt, locale)}</span>
        </span>
      ) : (
        t.time.never
      ),
    ],
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
    <section aria-label={t.userDetail.profile} className="flex flex-col gap-5 rounded-card bg-sheet p-5 md:gap-6 md:p-7">
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
      {/* Phone: avatar beside the email, copy as an icon in the corner; desktop: the full row. */}
      <div className="flex items-start gap-3.5 md:flex-wrap md:items-center md:gap-5">
        <Avatar seed={user.email} label={user.name || user.email} size={72} className="max-md:size-14 max-md:text-[22px]" />
        <div className="flex min-w-0 flex-1 flex-col gap-1.5 md:flex-[1_1_320px]">
          <h1 className="m-0 font-display text-[22px] leading-[1.2] font-semibold [overflow-wrap:anywhere] md:text-title">{emailParts(user.email)}</h1>
          <div className="flex flex-wrap items-center gap-2">
            {user.name && <span className="text-body text-ink2">{user.name}</span>}
            <UserStatusChip banned={user.banned} />
            {user.hasAiKey && <Chip icon="key">{t.userDetail.freeAi}</Chip>}
          </div>
        </div>
        <Button variant="secondary" icon="copy" onClick={onCopyEmail} className="max-md:hidden">
          {t.userDetail.copyEmail}
        </Button>
        <IconButton icon="copy" label={t.userDetail.copyEmail} onClick={onCopyEmail} className="flex-none md:hidden" />
      </div>
      <dl className="m-0 grid grid-cols-2 gap-x-4 gap-y-4 border-t border-track pt-5 md:grid-cols-[repeat(auto-fit,minmax(180px,1fr))] md:gap-5">
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
