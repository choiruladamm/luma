import { useI18n } from "../../i18n";
import { cn } from "../../lib/cn";
import { formatNumber } from "../../lib/format";
import { IconButton } from "./button";
import { Select } from "./select";

/** Page numbers to show: first, last, and a window around the current one; `null` = a gap. */
export function pageList(page: number, count: number): (number | null)[] {
  if (count <= 7) return Array.from({ length: count }, (_, i) => i + 1);
  const around = [page - 1, page, page + 1].filter((p) => p > 1 && p < count);
  const list: (number | null)[] = [1];
  if (around[0]! > 2) list.push(null);
  list.push(...around);
  if (around.at(-1)! < count - 1) list.push(null);
  list.push(count);
  return list;
}

/**
 * Table footer: "51–100 of 120", ‹ 1 … 4 5 6 … 10 ›, and an optional page size. Phones get the
 * compact "‹ Page 2 / 3 ›". Replaces the board's "Muat lagi" (docs/dashboard.md, UI).
 */
export function Pagination({ page, pageCount, total, pageSize, onPage, pageSizes, onPageSize }: { page: number; pageCount: number; total: number; pageSize: number; onPage: (page: number) => void; pageSizes?: number[]; onPageSize?: (size: number) => void }) {
  const { t, locale } = useI18n();
  const n = (v: number) => formatNumber(v, locale);
  const from = total === 0 ? 0 : (page - 1) * pageSize + 1;
  const to = Math.min(total, page * pageSize);
  return (
    <nav aria-label={t.common.pagination} className="flex flex-wrap items-center justify-between gap-3 px-6 py-4">
      <span className="text-caption text-ink2 tabular-nums">{t.common.range(n(from), n(to), n(total))}</span>
      <div className="flex items-center gap-1.5">
        {pageSizes && onPageSize && (
          <span className="mr-2 inline-flex items-center gap-2 text-caption text-ink2 max-md:hidden">
            <Select up hideLabel label={t.common.perPage} value={String(pageSize)} options={pageSizes.map((size) => [String(size), String(size)] as [string, string])} onChange={(v) => onPageSize(Number(v))} />
            {t.common.perPage}
          </span>
        )}
        <IconButton icon="back" label={t.common.prevPage} size="md" disabled={page <= 1} onClick={() => onPage(page - 1)} />
        <span className="px-2 text-caption font-medium tabular-nums md:hidden">{t.common.pageOf(n(page), n(pageCount))}</span>
        <ol className="m-0 flex list-none items-center gap-1 p-0 max-md:hidden">
          {pageList(page, pageCount).map((p, i) =>
            p === null ? (
              <li key={`gap-${i}`} aria-hidden="true" className="w-6 text-center text-ink2">
                …
              </li>
            ) : (
              <li key={p}>
                <button
                  type="button"
                  aria-label={t.common.goToPage(n(p))}
                  aria-current={p === page ? "page" : undefined}
                  onClick={() => onPage(p)}
                  className={cn("h-11 min-w-11 rounded-full px-2 text-body tabular-nums", p === page ? "bg-ink font-semibold text-canvas" : "text-ink hover:bg-muted")}
                >
                  {n(p)}
                </button>
              </li>
            ),
          )}
        </ol>
        <IconButton icon="chev" label={t.common.nextPage} size="md" disabled={page >= pageCount} onClick={() => onPage(page + 1)} />
      </div>
    </nav>
  );
}
