import { type ColumnDef, createColumnHelper, type RowData, tableFeatures, useTable } from "@tanstack/react-table";
import type { ReactNode } from "react";
import { Link, useNavigate } from "react-router";
import { useMediaQuery } from "../../hooks/use-media-query";
import { useI18n } from "../../i18n";
import { cn } from "../../lib/cn";
import { formatNumber } from "../../lib/format";
import { Icon } from "./icons";

// Core-only table: search and pagination happen on the server, so no row-model features.
export const features = tableFeatures({});
export type Features = typeof features;
export const columnHelper = <T extends RowData>() => createColumnHelper<Features, T>();

/**
 * Komponen 2, Tabel: sheet card radius 20, horizontal scroll (min 1040), header 13/500 ink2,
 * rows 60 tall with a track divider. With `rowHref` a whole row is one link (hover canvas +
 * underlined lead text, arrow at the end). Below 768px rows render as cards (`renderCard`).
 */
export function DataTable<T extends RowData>({ columns, data, label, rowHref, numeric = [], sortedBy, renderCard, footer, minWidth = 1040 }: { columns: ColumnDef<Features, T, any>[]; data: T[]; label: string; rowHref?: (row: T) => string; numeric?: string[]; sortedBy?: string; renderCard?: (row: T) => ReactNode; footer?: ReactNode; minWidth?: number }) {
  const table = useTable({ features, columns, data });
  const navigate = useNavigate();
  const narrow = useMediaQuery("(max-width: 767px)");
  const { t } = useI18n();

  if (narrow && renderCard) {
    return (
      <div>
        <ul aria-label={label} className="m-0 flex list-none flex-col gap-2 p-3">
          {data.map((row, i) => (
            <li key={i}>
              {rowHref ? (
                <Link to={rowHref(row)} className="block rounded-row bg-canvas p-4 text-ink no-underline hover:bg-muted">
                  {renderCard(row)}
                </Link>
              ) : (
                <div className="rounded-row bg-canvas p-4">{renderCard(row)}</div>
              )}
            </li>
          ))}
        </ul>
        {footer}
      </div>
    );
  }

  return (
    <div>
      <div className="overflow-x-auto">
        <table aria-label={label} className="w-full border-collapse" style={{ minWidth }}>
          <thead>
            {table.getHeaderGroups().map((group) => (
              <tr key={group.id}>
                {group.headers.map((header, i) => (
                  <th
                    key={header.id}
                    scope="col"
                    aria-sort={sortedBy === header.column.id ? "descending" : undefined}
                    className={cn("border-b border-track py-3 text-caption font-medium whitespace-nowrap", sortedBy === header.column.id ? "text-ink" : "text-ink2", numeric.includes(header.column.id) ? "text-right" : "text-left", i === 0 ? "pr-3 pl-6" : "px-3")}
                  >
                    {header.isPlaceholder ? null : <table.FlexRender header={header} />}
                    {sortedBy === header.column.id && <Icon name="down" size={14} className="ml-1 inline align-[-2px]" />}
                  </th>
                ))}
                {rowHref && (
                  <th scope="col" className="w-5 border-b border-track py-3 pr-6 pl-1">
                    <span className="sr-only">{t.common.open}</span>
                  </th>
                )}
              </tr>
            ))}
          </thead>
          <tbody>
            {table.getRowModel().rows.map((row) => {
              const href = rowHref?.(row.original);
              return (
                <tr key={row.id} onClick={href ? () => void navigate(href) : undefined} className={cn("group", href && "cursor-pointer hover:bg-canvas")}>
                  {row.getAllCells().map((cell, i) => (
                    <td key={cell.id} className={cn("h-[60px] border-b border-track py-2.5 text-body", numeric.includes(cell.column.id) ? "text-right tabular-nums" : "text-left", i === 0 ? "pr-3 pl-6" : "px-3")}>
                      {i === 0 && href ? (
                        <Link to={href} className="text-ink no-underline group-hover:[&_.lead]:underline" onClick={(e) => e.stopPropagation()}>
                          <table.FlexRender cell={cell} />
                        </Link>
                      ) : (
                        <table.FlexRender cell={cell} />
                      )}
                    </td>
                  ))}
                  {href && (
                    <td className="border-b border-track pr-6 pl-1 text-ink2">
                      <Icon name="chev" size={18} />
                    </td>
                  )}
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      {footer}
    </div>
  );
}

/** "Nampilin 10 dari 48" + "Muat lagi" (server cursor or client slice). */
export function LoadMore({ shown, total, onMore, loading }: { shown: number; total?: number; onMore?: () => void; loading?: boolean }) {
  const { t, locale } = useI18n();
  return (
    <div className="flex flex-wrap items-center justify-between gap-3 px-6 py-4">
      <span className="text-caption text-ink2 tabular-nums">
        {total === undefined ? t.common.showing(formatNumber(shown, locale)) : t.common.showingOf(formatNumber(shown, locale), formatNumber(total, locale))}
      </span>
      {onMore && (
        <button type="button" onClick={onMore} disabled={loading} className="inline-flex h-11 items-center gap-2 rounded-full bg-muted px-5 text-body font-medium text-ink hover:bg-track disabled:text-ink2">
          {loading ? t.common.loadingMore : t.common.loadMore}
        </button>
      )}
    </div>
  );
}
