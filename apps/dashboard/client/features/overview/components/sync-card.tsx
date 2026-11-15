import { Card, CardHeader } from "../../../components/ui/card";
import { Chip } from "../../../components/ui/chip";
import { Skeleton } from "../../../components/ui/skeleton";
import { useI18n } from "../../../i18n";
import { formatNumber } from "../../../lib/format";

const HATCH = { background: "repeating-linear-gradient(135deg, var(--c-track) 0 3px, var(--c-canvas) 3px 7px)" };

/**
 * Sync rows written today vs the account-wide D1 write limit. The board's 7-day chart needs
 * history the backend doesn't keep (only today's counter), so this is the today capsule alone.
 */
export function SyncCard({ data, limit = 100_000 }: { data?: { rows: number; limit: number }; limit?: number }) {
  const { locale } = useI18n();
  if (!data) return <SyncCardSkeleton limit={limit} />;
  const { rows } = data;
  limit = data.limit;
  const pct = Math.min(100, (rows / limit) * 100);
  const used = rows > 0 && pct < 1 ? "<1" : Math.round(pct).toString();
  return (
    <Card aria-labelledby="h-sync" className="gap-5">
      <CardHeader id="h-sync" title="Sync" subtitle={`Hari ini · batas ${formatNumber(limit, locale)} baris per hari buat semua user`} />
      <div className="flex flex-wrap items-baseline gap-2.5">
        <span className="text-stat font-semibold tabular-nums">{formatNumber(rows, locale)}</span>
        <span className="text-body font-medium text-ink2 tabular-nums">baris hari ini · sisa {formatNumber(Math.max(0, limit - rows), locale)}</span>
        <Chip>{used}% kepakai</Chip>
      </div>
      <div role="img" aria-label={`${formatNumber(rows, locale)} dari ${formatNumber(limit, locale)} baris sync hari ini, ${used}% kepakai.`} className="relative h-14 overflow-hidden rounded-full" style={HATCH}>
        <div className="h-full rounded-full border-[1.5px] border-outline bg-accent" style={{ width: `max(${pct}%, ${rows > 0 ? "56px" : "0px"})` }} />
      </div>
      <Legend />
    </Card>
  );
}

/** Board 12: header, capsule track and legend stay; the numbers pulse. */
function SyncCardSkeleton({ limit }: { limit: number }) {
  const { locale } = useI18n();
  return (
    <Card aria-labelledby="h-sync" aria-busy="true" className="gap-5">
      <CardHeader id="h-sync" title="Sync" subtitle={`Hari ini · batas ${formatNumber(limit, locale)} baris per hari buat semua user`} />
      <div className="flex flex-wrap items-center gap-2.5">
        <Skeleton className="h-9 w-[150px] rounded-[10px]" />
        <Skeleton className="h-3.5 w-[190px]" />
      </div>
      <div aria-hidden="true" className="h-14 rounded-full" style={HATCH} />
      <Legend />
    </Card>
  );
}

function Legend() {
  return (
      <div className="flex flex-wrap items-center justify-between gap-3 text-caption text-ink2">
        <div className="flex flex-wrap gap-4">
          <span className="inline-flex items-center gap-1.5">
            <span aria-hidden="true" className="size-2.5 rounded-full border-[1.5px] border-outline bg-accent" />
            Ditulis hari ini
          </span>
          <span className="inline-flex items-center gap-1.5">
            <span aria-hidden="true" className="size-2.5 rounded-full" style={HATCH} />
            Sisa batas
          </span>
        </div>
        <span>Reset tiap 00.00 UTC (07.00 WIB)</span>
      </div>
  );
}
