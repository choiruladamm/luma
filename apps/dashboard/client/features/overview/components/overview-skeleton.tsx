import { Skeleton } from "../../../components/ui/skeleton";

const STATS = ["User terdaftar", "Baru 7 hari", "Di-ban", "Penyimpanan", "Kode undangan"];

/** Board 12: real labels stay, values pulse. */
export function OverviewStatsSkeleton() {
  return (
    <div aria-busy="true" aria-label="Lagi muat ringkasan" className="grid grid-cols-[repeat(auto-fit,minmax(200px,1fr))] gap-4">
      {STATS.map((label) => (
        <div key={label} className="flex min-h-[140px] flex-col gap-3.5 rounded-card bg-sheet px-[22px] py-5">
          <span className="text-body font-medium text-ink2">{label}</span>
          <Skeleton className="h-9 w-20" />
          <Skeleton className="mt-auto h-3 w-28" />
        </div>
      ))}
    </div>
  );
}

export function CardSkeleton({ title, className }: { title: string; className?: string }) {
  return (
    <section aria-busy="true" className={`flex flex-col gap-4 rounded-card bg-sheet p-6 ${className ?? ""}`}>
      <h2 className="m-0 text-card font-semibold">{title}</h2>
      <Skeleton className="h-9 w-40" />
      <Skeleton className="h-14 w-full" />
    </section>
  );
}
