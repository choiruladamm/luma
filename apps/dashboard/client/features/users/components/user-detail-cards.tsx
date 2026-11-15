import { Card, CardHeader } from "../../../components/ui/card";
import { Icon } from "../../../components/ui/icons";
import { ProgressBar } from "../../../components/ui/meter";
import { type Messages, useI18n } from "../../../i18n";
import { cn } from "../../../lib/cn";
import { formatBytes, formatDate, formatRelative, formatUsd } from "../../../lib/format";
import type { UserDetail } from "../api/users-api";

/** Also used by the loading skeleton, so both share the exact box. */
export function NumberCard({ title, value, children, wide }: { title: string; value: React.ReactNode; children?: React.ReactNode; wide?: boolean }) {
  return (
    <section className={cn("flex min-w-0 flex-[1_1_260px] flex-col gap-3 rounded-card bg-sheet p-4 md:p-6", wide && "col-span-2")}>
      <h2 className="m-0 text-body font-semibold text-ink2">{title}</h2>
      <span className="text-[24px] leading-none font-semibold tracking-[-0.03em] tabular-nums md:text-[30px]">{value}</span>
      {children}
    </section>
  );
}

/** Usage cards sit in `NUMBER_GRID`: two columns on phones (the AI card spans both), a wrapping row on desktop. */
export const NUMBER_GRID = "grid grid-cols-2 gap-3 md:flex md:flex-wrap md:gap-4";

/** File and sync usage; the share of all files shows only when the overview is already cached. */
export function UsageCards({ user, totalR2 }: { user: UserDetail; totalR2?: number }) {
  const { t, locale } = useI18n();
  const share = totalR2 ? (user.r2Bytes / totalR2) * 100 : undefined;
  return (
    <>
      <NumberCard title={t.userDetail.bookFiles} value={formatBytes(user.r2Bytes, locale)}>
        {share !== undefined && (
          <>
            <ProgressBar value={share} label={t.userDetail.shareBar} />
            <span className="text-caption text-ink2">{t.userDetail.share(share < 1 && user.r2Bytes > 0 ? "<1" : String(Math.round(share)))}</span>
          </>
        )}
      </NumberCard>
      <NumberCard title={t.users.syncData} value={formatBytes(user.syncBytes, locale)}>
        <span className="text-caption text-ink2">{t.userDetail.syncNote}</span>
      </NumberCard>
    </>
  );
}

/** Subsidized key only (an own key never reaches the server): today's use vs the daily limit. */
export function AiCard({ ai }: { ai: UserDetail["ai"] }) {
  const { t, locale } = useI18n();
  return (
    <NumberCard wide title={t.userDetail.freeAi} value={ai ? (ai.usageDaily === null ? "—" : formatUsd(ai.usageDaily, locale)) : t.userDetail.aiNone}>
      {ai ? (
        <>
          {ai.usageDaily !== null && <ProgressBar value={(ai.usageDaily / ai.limit) * 100} label={t.userDetail.aiUsageBar} />}
          <span className="text-caption text-ink2">
            {ai.usageDaily === null ? `${t.userDetail.aiUsageFailed} ` : `${t.userDetail.aiTodayOf(formatUsd(ai.limit, locale))} · `}
            {t.userDetail.aiKeyUntil(formatDate(ai.expiresAt, locale))}
          </span>
        </>
      ) : (
        <span className="text-caption text-ink2">{t.userDetail.aiNoKey}</span>
      )}
    </NumberCard>
  );
}

/** "Luma/0.3.0 (+mailto:…)" → "App Luma 0.3.0"; browsers and tools keep a short raw label. */
export function deviceLabel(userAgent: string | null, t: Messages) {
  if (!userAgent) return t.userDetail.unknownDevice;
  const app = userAgent.match(/^Luma\/([\w.]+)/);
  if (app) return t.userDetail.lumaApp(app[1]!);
  if (userAgent.includes("Mozilla")) return "Browser";
  return userAgent.split(" ")[0]!;
}

/** Sessions per device (in scope, not on the board): newest first, max 50 from the API. */
export function SessionsCard({ sessions }: { sessions: UserDetail["sessions"] }) {
  const i18n = useI18n();
  const { t, locale } = i18n;
  return (
    <Card aria-labelledby="h-sesi" className="gap-3">
      <CardHeader id="h-sesi" title={t.userDetail.devices} subtitle={t.userDetail.sessions(sessions.length)} />
      {sessions.length === 0 ? (
        <span className="text-body text-ink2">{t.userDetail.noSessions}</span>
      ) : (
        <ul className="m-0 flex list-none flex-col gap-2 p-0">
          {sessions.map((s, i) => (
            <li key={i} className="flex min-h-14 items-center gap-3 rounded-row bg-muted py-2 pr-4 pl-2">
              <span className="flex size-10 flex-none items-center justify-center rounded-tile-lg bg-sheet">
                <Icon name={s.userAgent?.startsWith("Luma/") ? "phone" : "monitor"} size={20} />
              </span>
              <span className="flex min-w-0 flex-1 flex-col gap-0.5">
                <span className="truncate text-body font-semibold" title={s.userAgent ?? undefined}>
                  {deviceLabel(s.userAgent, t)}
                </span>
                <span className="truncate text-caption text-ink2">
                  {t.userDetail.signedIn(formatDate(s.createdAt, locale))}
                  {s.ipAddress ? ` · ${s.ipAddress}` : ""}
                </span>
              </span>
              <span className="text-caption whitespace-nowrap text-ink2">{formatRelative(s.updatedAt, i18n)}</span>
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}
