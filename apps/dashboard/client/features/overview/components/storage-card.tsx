import { Card, CardHeader } from "../../../components/ui/card";
import { Gauge } from "../../../components/ui/meter";
import { Skeleton } from "../../../components/ui/skeleton";
import { formatBytes } from "../../../lib/format";

/** Half gauge: ink = book files (R2), pink = sync data (D1). No data yet → board 12 skeleton. */
export function StorageCard({ data }: { data?: { r2Bytes: number; syncBytes: number } }) {
  const total = data ? data.r2Bytes + data.syncBytes : 0;
  const share = (n: number) => (total > 0 ? n / total : 0);
  return (
    <Card aria-labelledby="h-simpan" aria-busy={!data || undefined}>
      <CardHeader id="h-simpan" title="Penyimpanan" />
      <Gauge
        label={data ? `Total ${formatBytes(total)}: file buku ${formatBytes(data.r2Bytes)}, data sync ${formatBytes(data.syncBytes)}.` : "Lagi muat penyimpanan"}
        parts={data ? [{ value: share(data.r2Bytes), color: "var(--c-ink)" }, { value: share(data.syncBytes), color: "var(--c-pink)" }] : []}
      >
        {data ? <span className="text-[26px] leading-none font-semibold tracking-[-0.02em] tabular-nums">{formatBytes(total)}</span> : <Skeleton className="h-[26px] w-[88px] rounded-[8px]" />}
        <span className="text-caption text-ink2">total</span>
      </Gauge>
      <div className="flex flex-col gap-2">
        {(
          [
            ["File buku", data?.r2Bytes, "bg-ink"],
            ["Data sync", data?.syncBytes, "bg-pink"],
          ] as const
        ).map(([label, bytes, dot]) => (
          <div key={label} className="flex items-center justify-between text-body">
            <span className="inline-flex items-center gap-2 font-medium text-ink2">
              <span aria-hidden="true" className={`size-2.5 rounded-full ${dot}`} />
              {label}
            </span>
            {bytes === undefined ? <Skeleton className="h-3 w-14" /> : <span className="font-semibold tabular-nums">{formatBytes(bytes)}</span>}
          </div>
        ))}
      </div>
    </Card>
  );
}
