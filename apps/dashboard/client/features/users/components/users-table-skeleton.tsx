import { Skeleton } from "../../../components/ui/skeleton";

const HEADERS = ["User", "Daftar", "Terakhir aktif", "File", "Data sync", "Key AI", "Status"];

/** Board 13: the real table frame (headers) stays, only the values are sand blocks. */
export function UsersTableSkeleton({ rows = 6 }: { rows?: number }) {
  return (
    <div aria-busy="true" aria-label="Lagi muat daftar user" className="overflow-x-auto">
      <table className="w-full min-w-[1040px] border-collapse">
        <thead>
          <tr>
            {HEADERS.map((h, i) => (
              <th key={h} scope="col" className={i === 0 ? "border-b border-track py-3 pr-3 pl-6 text-left text-caption font-medium text-ink2" : "border-b border-track px-3 py-3 text-left text-caption font-medium text-ink2"}>
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {Array.from({ length: rows }, (_, r) => (
            <tr key={r}>
              <td className="h-[60px] border-b border-track py-2.5 pr-3 pl-6">
                <span className="flex items-center gap-3">
                  <Skeleton className="size-9" />
                  <span className="flex flex-col gap-1.5">
                    <Skeleton className="h-3 w-44" />
                    <Skeleton className="h-2.5 w-24" />
                  </span>
                </span>
              </td>
              {HEADERS.slice(1).map((h) => (
                <td key={h} className="border-b border-track px-3">
                  <Skeleton className="h-3 w-16" />
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
