import { Card, CardHeader } from "../../../components/ui/card";
import { ProgressBar } from "../../../components/ui/meter";
import { Skeleton } from "../../../components/ui/skeleton";
import { useI18n } from "../../../i18n";
import { formatDate, formatUsd } from "../../../lib/format";

/** Workspace spend of the subsidized keys this month vs the guardrail budget (runs a day behind). */
export function AiSpendCard({
  ai,
}: {
  ai?: { spend_usd: number | null; budget_usd: number; as_of: string };
}) {
  const { t, locale } = useI18n();
  if (!ai) {
    return (
      <Card aria-labelledby="h-ai" aria-busy="true" className="gap-3">
        <CardHeader id="h-ai" title={t.overview.aiTitle} subtitle={t.overview.thisMonth} />
        <Skeleton className="h-[30px] w-[150px] rounded-[10px]" />
        <Skeleton className="h-2 w-full" />
      </Card>
    );
  }
  const pct = ai.spend_usd === null ? 0 : (ai.spend_usd / ai.budget_usd) * 100;
  return (
    <Card aria-labelledby="h-ai" className="gap-3">
      <CardHeader
        id="h-ai"
        title={t.overview.aiTitle}
        subtitle={t.overview.thisMonthUntil(formatDate(ai.as_of, locale))}
      />
      {ai.spend_usd === null ? (
        <span className="text-body text-ink2">{t.overview.aiFailed}</span>
      ) : (
        <>
          <div className="flex flex-wrap items-baseline gap-2">
            <span className="text-[30px] leading-none font-semibold tracking-[-0.03em] tabular-nums">
              {formatUsd(ai.spend_usd, locale)}
            </span>
            <span className="text-body text-ink2">
              {t.overview.of(formatUsd(ai.budget_usd, locale))}
            </span>
          </div>
          <ProgressBar value={pct} label={t.overview.aiBudgetBar} />
          <span className="text-caption text-ink2">{t.overview.aiLag}</span>
        </>
      )}
    </Card>
  );
}
