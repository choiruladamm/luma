import { Card, CardHeader } from "../../../components/ui/card";
import { ProgressBar } from "../../../components/ui/meter";
import { Skeleton } from "../../../components/ui/skeleton";
import { useI18n } from "../../../i18n";
import { formatDate, formatUsd } from "../../../lib/format";

/** Workspace spend of the subsidized keys this month vs the guardrail budget (runs a day behind). */
export function AiSpendCard({ ai }: { ai?: { spendUsd: number | null; budgetUsd: number; asOf: string } }) {
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
  const pct = ai.spendUsd === null ? 0 : (ai.spendUsd / ai.budgetUsd) * 100;
  return (
    <Card aria-labelledby="h-ai" className="gap-3">
      <CardHeader id="h-ai" title={t.overview.aiTitle} subtitle={t.overview.thisMonthUntil(formatDate(ai.asOf, locale))} />
      {ai.spendUsd === null ? (
        <span className="text-body text-ink2">{t.overview.aiFailed}</span>
      ) : (
        <>
          <div className="flex flex-wrap items-baseline gap-2">
            <span className="text-[30px] leading-none font-semibold tracking-[-0.03em] tabular-nums">{formatUsd(ai.spendUsd, locale)}</span>
            <span className="text-body text-ink2">{t.overview.of(formatUsd(ai.budgetUsd, locale))}</span>
          </div>
          <ProgressBar value={pct} label={t.overview.aiBudgetBar} />
          <span className="text-caption text-ink2">{t.overview.aiLag}</span>
        </>
      )}
    </Card>
  );
}
