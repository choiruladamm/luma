import { Card, CardHeader } from "../../../components/ui/card";
import { Gauge } from "../../../components/ui/meter";
import { formatBytes } from "../../../lib/format";

/** Half gauge: ink = book files (R2), pink = sync data (D1). */
export function StorageCard({ r2Bytes, syncBytes }: { r2Bytes: number; syncBytes: number }) {
  const total = r2Bytes + syncBytes;
  const share = (n: number) => (total > 0 ? n / total : 0);
  return (
    <Card aria-labelledby="h-simpan">
      <CardHeader id="h-simpan" title="Penyimpanan" />
      <Gauge
        label={`Total ${formatBytes(total)}: file buku ${formatBytes(r2Bytes)}, data sync ${formatBytes(syncBytes)}.`}
        parts={[
          { value: share(r2Bytes), color: "var(--c-ink)" },
          { value: share(syncBytes), color: "var(--c-pink)" },
        ]}
      >
        <span className="text-[26px] leading-none font-semibold tracking-[-0.02em] tabular-nums">{formatBytes(total)}</span>
        <span className="text-caption text-ink2">total</span>
      </Gauge>
      <div className="flex flex-col gap-2">
        {[
          ["File buku", r2Bytes, "bg-ink"],
          ["Data sync", syncBytes, "bg-pink"],
        ].map(([label, bytes, dot]) => (
          <div key={label as string} className="flex items-center justify-between text-body">
            <span className="inline-flex items-center gap-2 font-medium text-ink2">
              <span aria-hidden="true" className={`size-2.5 rounded-full ${dot}`} />
              {label}
            </span>
            <span className="font-semibold tabular-nums">{formatBytes(bytes as number)}</span>
          </div>
        ))}
      </div>
    </Card>
  );
}
