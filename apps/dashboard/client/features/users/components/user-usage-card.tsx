import { Card, CardHeader } from "../../../components/ui/card";
import { Skeleton } from "../../../components/ui/skeleton";
import { ErrorState } from "../../../components/ui/states";
import { type Messages, useI18n } from "../../../i18n";
import { errorText } from "../../../lib/api-error";
import { formatDate, formatNumber, formatUsd } from "../../../lib/format";
import type { UserUsage } from "../api/users-api";

// The app's feature names; product names, so the same in every language.
const FEATURES: Record<string, string> = {
  group: "Artinya",
  breakdown: "Bedahin",
  chat: "Ngobrolin",
};

const keyLabel = (source: string, t: Messages) => {
  if (source === "own") return t.userDetail.keyOwn;
  if (source === "subsidy") return t.userDetail.keySubsidy;
  return t.userDetail.keyUnknown;
};

type Row = { label: string; title?: string; value: string; note: string };

function UsageList({ title, rows }: { title: string; rows: Row[] }) {
  if (rows.length === 0) return null;
  return (
    <div className="flex flex-col gap-2">
      <h3 className="m-0 text-body font-semibold text-ink2">{title}</h3>
      <ul className="m-0 flex list-none flex-col gap-2 p-0">
        {rows.map((r, i) => (
          <li key={i} className="flex min-h-12 items-center gap-3 rounded-row bg-muted px-4 py-2">
            <span className="min-w-0 flex-1 truncate text-body font-semibold" title={r.title}>
              {r.label}
            </span>
            <span className="flex flex-col items-end text-right">
              <span className="text-body tabular-nums">{r.value}</span>
              <span className="text-caption text-ink2 tabular-nums">{r.note}</span>
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}

function Stat({ label, value, note }: { label: string; value: string; note?: string }) {
  return (
    <div className="flex min-w-0 flex-col gap-1 rounded-row bg-muted p-4">
      <span className="text-caption text-ink2">{label}</span>
      <span className="text-[22px] leading-none font-semibold tracking-[-0.02em] tabular-nums">
        {value}
      </span>
      {note && <span className="text-caption text-ink2">{note}</span>}
    </div>
  );
}

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
  const minutes = (s: number) => t.userDetail.minutes(Math.round(s / 60));
  const calls = (n: number, failed: number) =>
    failed > 0
      ? `${t.userDetail.calls(n)} · ${t.userDetail.failedCalls(failed)}`
      : t.userDetail.calls(n);

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
        <Stat
          label={t.userDetail.aiCalls}
          value={formatNumber(totals.calls, locale)}
          note={totals.calls > 0 ? t.userDetail.aiFailed(String(failedPct)) : undefined}
        />
        <Stat
          label={t.userDetail.aiCost}
          value={usd(totals.cost_usd)}
          note={totals.cost_usd === null ? t.userDetail.costUnknown : undefined}
        />
        <Stat label={t.userDetail.readingTime} value={minutes(totals.reading_seconds)} />
        <Stat
          label={t.userDetail.activeDays(totals.active_days)}
          value={formatNumber(totals.active_days, locale)}
        />
      </div>
      <UsageList
        title={t.userDetail.byFeature}
        rows={usage.features.map((f) => ({
          label: FEATURES[f.feature] ?? f.feature,
          value: usd(f.cost_usd),
          note: calls(f.calls, f.failed),
        }))}
      />
      <UsageList
        title={t.userDetail.byModel}
        rows={usage.models.map((m) => ({
          label: m.model,
          title: m.model,
          value: usd(m.cost_usd),
          note: calls(m.calls, m.failed),
        }))}
      />
      <UsageList
        title={t.userDetail.byKey}
        rows={usage.key_sources.map((k) => ({
          label: keyLabel(k.key_source, t),
          value: usd(k.cost_usd),
          note: calls(k.calls, k.failed),
        }))}
      />
      <UsageList
        title={t.userDetail.books}
        rows={usage.books.map((b) => {
          const label = b.book_title ?? t.userDetail.deletedBook;
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
