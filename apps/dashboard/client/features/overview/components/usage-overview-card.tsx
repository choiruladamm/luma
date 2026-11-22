import { Card, CardHeader } from "../../../components/ui/card";
import { Skeleton } from "../../../components/ui/skeleton";
import { ErrorState } from "../../../components/ui/states";
import { MiniStat, UsageList } from "../../../components/ui/usage-list";
import { useI18n } from "../../../i18n";
import { errorText } from "../../../lib/api-error";
import { formatDate, formatNumber, formatUsd } from "../../../lib/format";
import { FEATURE_NAMES, keySourceLabel } from "../../../lib/usage";
import type { UsageOverview } from "../api/overview-api";

const percent = (part: number, whole: number) =>
  whole > 0 ? String(Math.round((part / whole) * 100)) : "0";

/** One bar per reported day, height relative to the most expensive day. */
function CostBars({ days }: { days: UsageOverview["days"] }) {
  const { t, locale } = useI18n();
  const max = Math.max(...days.map((d) => d.cost_usd ?? 0));
  if (max <= 0) return null;
  return (
    <div className="flex flex-col gap-2">
      <h3 className="m-0 text-body font-semibold text-ink2">{t.overview.costPerDay}</h3>
      <ul
        aria-label={t.overview.costPerDay}
        className="m-0 flex h-24 list-none items-end gap-1 rounded-row bg-muted p-3"
      >
        {days.map((d) => {
          const label = t.overview.dayBar(
            formatDate(d.day, locale),
            d.cost_usd === null ? "—" : formatUsd(d.cost_usd, locale),
          );
          return (
            <li
              key={d.day}
              aria-label={label}
              title={label}
              className="min-w-1 flex-1 rounded-t-[4px] bg-accent"
              // A data-driven size, not a design value: the bar's share of the busiest day.
              style={{ height: `${Math.max(4, ((d.cost_usd ?? 0) / max) * 100)}%` }}
            />
          );
        })}
      </ul>
    </div>
  );
}

/**
 * Every user's usage reports (`usage_daily`) over the last 30 days, beside OpenRouter's spend:
 * the gap is own-key calls plus calls that report no cost. Not on the design board; built
 * from the user detail's usage card.
 */
export function UsageOverviewCard({
  usage,
  error,
  onRetry,
  openRouterSpend,
}: {
  usage: UsageOverview | undefined;
  error: Error | null;
  onRetry: () => void;
  openRouterSpend: number | null | undefined;
}) {
  const { t, locale } = useI18n();
  const usd = (v: number | null) => (v === null ? "—" : formatUsd(v, locale));
  const minutes = (s: number) => t.usage.minutes(Math.round(s / 60));
  const calls = (n: number, failed: number) =>
    failed > 0 ? `${t.usage.calls(n)} · ${t.usage.failedCalls(failed)}` : t.usage.calls(n);
  const header = (subtitle?: string) => (
    <CardHeader id="h-usage" title={t.overview.usageTitle} subtitle={subtitle} />
  );

  if (error && !usage) {
    return (
      <Card aria-labelledby="h-usage">
        {header()}
        <ErrorState message={errorText(error, t)} onRetry={onRetry} />
      </Card>
    );
  }
  if (!usage) {
    return (
      <Card aria-labelledby="h-usage" aria-busy="true" aria-label={t.overview.usageLoading}>
        {header()}
        <Skeleton className="h-20 w-full" />
      </Card>
    );
  }

  const { totals } = usage;
  const days = Math.round((Date.parse(usage.to) - Date.parse(usage.from)) / 86_400_000) + 1;
  const subtitle = t.overview.usageRange(days);
  if (totals.active_users === 0) {
    return (
      <Card aria-labelledby="h-usage">
        {header(subtitle)}
        <span className="text-body text-ink2">{t.overview.usageNone}</span>
      </Card>
    );
  }

  return (
    <Card aria-labelledby="h-usage">
      {header(subtitle)}
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <MiniStat
          label={t.usage.aiCalls}
          value={formatNumber(totals.calls, locale)}
          note={t.usage.aiFailed(percent(totals.failed, totals.calls))}
        />
        <MiniStat
          label={t.overview.reportedMonth}
          value={usd(usage.month.cost_usd)}
          note={
            typeof openRouterSpend === "number"
              ? t.overview.openRouterMonth(formatUsd(openRouterSpend, locale))
              : undefined
          }
        />
        <MiniStat
          label={t.overview.activeUsers}
          value={formatNumber(usage.active.week, locale)}
          note={t.overview.activeNote(
            formatNumber(usage.active.day, locale),
            formatNumber(usage.active.week, locale),
          )}
        />
        <MiniStat label={t.usage.readingTime} value={minutes(totals.reading_seconds)} />
      </div>
      <span className="text-caption text-ink2">{t.overview.gapNote}</span>
      <CostBars days={usage.days} />
      <UsageList
        title={t.usage.byFeature}
        rows={usage.features.map((f) => ({
          label: FEATURE_NAMES[f.feature] ?? f.feature,
          value: usd(f.cost_usd),
          note: calls(f.calls, f.failed),
        }))}
      />
      <UsageList
        title={t.usage.byModel}
        rows={usage.models.map((m) => ({
          label: m.model,
          title: m.model,
          value: usd(m.cost_usd),
          note: `${calls(m.calls, m.failed)} · ${t.usage.aiFailed(percent(m.failed, m.calls))}`,
        }))}
      />
      <UsageList
        title={t.usage.byKey}
        rows={usage.key_sources.map((k) => ({
          label: keySourceLabel(k.key_source, t),
          value: usd(k.cost_usd),
          note: t.overview.keyShare(percent(k.calls, totals.calls)),
        }))}
      />
      <UsageList
        title={t.overview.topUsers}
        rows={usage.top_users.map((u) => ({
          label: u.name || u.email,
          title: u.email,
          href: `/users/${u.id}`,
          value: usd(u.cost_usd),
          note: calls(u.calls, u.failed),
        }))}
      />
      <UsageList
        title={t.overview.topBooks}
        rows={usage.top_books.map((b) => {
          const label = b.book_title ?? t.usage.deletedBook;
          return {
            label,
            title: label,
            value: minutes(b.reading_seconds),
            note: t.overview.readers(b.readers),
          };
        })}
      />
    </Card>
  );
}
