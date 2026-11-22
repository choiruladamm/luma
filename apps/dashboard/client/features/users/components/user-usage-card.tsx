import { Card, CardHeader } from "../../../components/ui/card";
import { Skeleton } from "../../../components/ui/skeleton";
import { MiniStat, UsageList } from "../../../components/ui/usage-list";
import { ErrorState } from "../../../components/ui/states";
import { useI18n } from "../../../i18n";
import { errorText } from "../../../lib/api-error";
import { FEATURE_NAMES, keySourceLabel } from "../../../lib/usage";
import { formatDate, formatNumber, formatUsd } from "../../../lib/format";
import type { UserUsage } from "../api/users-api";

/**
 * The app's own usage reports (`usage_daily`): AI requests, cost, and reading per feature, model,
 * key, and book, own keys included. Not on the design board; built from the board's list rows.
 */
export function UsageCard({
  usage,
  error,
  onRetry,
}: {
  usage: UserUsage | undefined;
  error: Error | null;
  onRetry: () => void;
}) {
  const { t, locale } = useI18n();
  const usd = (v: number | null) => (v === null ? "—" : formatUsd(v, locale));
  const minutes = (s: number) => t.usage.minutes(Math.round(s / 60));
  const calls = (n: number, failed: number) =>
    failed > 0 ? `${t.usage.calls(n)} · ${t.usage.failedCalls(failed)}` : t.usage.calls(n);

  const header = (subtitle?: string) => (
    <CardHeader id="h-usage" title={t.userDetail.usageTitle} subtitle={subtitle} />
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
      <Card aria-labelledby="h-usage" aria-busy="true" aria-label={t.userDetail.usageLoading}>
        {header()}
        <Skeleton className="h-20 w-full" />
      </Card>
    );
  }

  const { totals } = usage;
  const days = Math.round((Date.parse(usage.to) - Date.parse(usage.from)) / 86_400_000) + 1;
  const range = t.userDetail.usageRange(days);
  const subtitle = totals.last_day
    ? `${range} · ${t.userDetail.usageLastDay(formatDate(totals.last_day, locale))}`
    : range;
  if (totals.active_days === 0) {
    return (
      <Card aria-labelledby="h-usage">
        {header(subtitle)}
        <span className="text-body text-ink2">{t.userDetail.usageNone}</span>
      </Card>
    );
  }

  const failedPct = totals.calls > 0 ? Math.round((totals.failed / totals.calls) * 100) : 0;
  return (
    <Card aria-labelledby="h-usage">
      {header(subtitle)}
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <MiniStat
          label={t.usage.aiCalls}
          value={formatNumber(totals.calls, locale)}
          note={totals.calls > 0 ? t.usage.aiFailed(String(failedPct)) : undefined}
        />
        <MiniStat
          label={t.usage.aiCost}
          value={usd(totals.cost_usd)}
          note={totals.cost_usd === null ? t.usage.costUnknown : undefined}
        />
        <MiniStat label={t.usage.readingTime} value={minutes(totals.reading_seconds)} />
        <MiniStat
          label={t.userDetail.activeDays(totals.active_days)}
          value={formatNumber(totals.active_days, locale)}
        />
      </div>
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
          note: calls(m.calls, m.failed),
        }))}
      />
      <UsageList
        title={t.usage.byKey}
        rows={usage.key_sources.map((k) => ({
          label: keySourceLabel(k.key_source, t),
          value: usd(k.cost_usd),
          note: calls(k.calls, k.failed),
        }))}
      />
      <UsageList
        title={t.usage.books}
        rows={usage.books.map((b) => {
          const label = b.book_title ?? t.usage.deletedBook;
          return {
            label,
            title: label,
            value: minutes(b.reading_seconds),
            note: `${calls(b.calls, b.failed)} · ${usd(b.cost_usd)}`,
          };
        })}
      />
    </Card>
  );
}
