import { Card, CardHeader } from "../../../components/ui/card";
import { ProgressBar } from "../../../components/ui/meter";
import { formatDate, formatUsd } from "../../../lib/format";

/** Workspace spend of the subsidized keys this month vs the guardrail budget (runs a day behind). */
export function AiSpendCard({ ai }: { ai: { spendUsd: number | null; budgetUsd: number; asOf: string } }) {
  const pct = ai.spendUsd === null ? 0 : (ai.spendUsd / ai.budgetUsd) * 100;
  return (
    <Card aria-labelledby="h-ai" className="gap-3">
      <CardHeader id="h-ai" title="Kuota AI gratis" subtitle={`Bulan ini · sampai ${formatDate(ai.asOf)}`} />
      {ai.spendUsd === null ? (
        <span className="text-body text-ink2">Angka OpenRouter gagal dimuat. Coba muat ulang nanti.</span>
      ) : (
        <>
          <div className="flex flex-wrap items-baseline gap-2">
            <span className="text-[30px] leading-none font-semibold tracking-[-0.03em] tabular-nums">{formatUsd(ai.spendUsd)}</span>
            <span className="text-body text-ink2">dari {formatUsd(ai.budgetUsd)}</span>
          </div>
          <ProgressBar value={pct} label="Pemakaian budget AI bulan ini" />
          <span className="text-caption text-ink2">Data OpenRouter cuma sampai kemarin.</span>
        </>
      )}
    </Card>
  );
}
