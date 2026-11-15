import { Icon } from "../../../components/ui/icons";
import { Skeleton } from "../../../components/ui/skeleton";
import { useI18n } from "../../../i18n";

// Same columns as user-columns.tsx; `sorted` marks "Daftar" (newest first).
const HEADERS = [
  ["user", "left"],
  ["joined", "left"],
  ["lastActive", "left"],
  ["files", "right"],
  ["syncData", "right"],
  ["aiKey", "left"],
  ["status", "left"],
] as const;
// Board 13: email widths vary per row so the block reads as a list, not a grid.
const EMAIL_WIDTHS = [168, 140, 184, 152, 176, 132];

/** Board 13: the real table frame (headers, sort mark) stays; only the values are sand blocks. */
export function UsersTableSkeleton({ rows = 8 }: { rows?: number }) {
  const { t } = useI18n();
  return (
    <div aria-busy="true" aria-label={t.users.loading} className="overflow-x-auto">
      <table className="w-full min-w-[1040px] border-collapse">
        <thead>
          <tr>
            {HEADERS.map(([h, align], i) => (
              <th key={h} scope="col" aria-sort={h === "joined" ? "descending" : undefined} className={`border-b border-track py-3 text-caption font-medium whitespace-nowrap ${h === "joined" ? "text-ink" : "text-ink2"} ${align === "right" ? "text-right" : "text-left"} ${i === 0 ? "pr-3 pl-6" : "px-3"}`}>
                {t.users[h]}
                {h === "joined" && <Icon name="down" size={14} className="ml-1 inline align-[-2px]" />}
              </th>
            ))}
            <th scope="col" className="w-5 border-b border-track py-3 pr-6 pl-1">
              <span className="sr-only">{t.common.open}</span>
            </th>
          </tr>
        </thead>
        <tbody>
          {Array.from({ length: rows }, (_, r) => (
            <tr key={r}>
              <td className="h-[60px] border-b border-track pr-3 pl-6">
                <span className="flex items-center gap-3">
                  <Skeleton className="size-9 flex-none" />
                  <span className="flex flex-col gap-1.5">
                    <Skeleton className="h-3" style={{ width: EMAIL_WIDTHS[r % EMAIL_WIDTHS.length] }} />
                    <Skeleton className="h-2.5 w-24" />
                  </span>
                </span>
              </td>
              <td className="border-b border-track px-3"><Skeleton className="h-3 w-[84px]" /></td>
              <td className="border-b border-track px-3"><Skeleton className="h-3 w-[72px]" /></td>
              <td className="border-b border-track px-3"><Skeleton className="ml-auto h-3 w-12" /></td>
              <td className="border-b border-track px-3"><Skeleton className="ml-auto h-3 w-11" /></td>
              <td className="border-b border-track px-3"><Skeleton className="h-3 w-16" /></td>
              <td className="border-b border-track px-3"><Skeleton className="h-6 w-[68px]" /></td>
              <td className="border-b border-track pr-6 pl-1" />
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
