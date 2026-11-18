import {
  type ColumnDef,
  createColumnHelper,
  type RowData,
  tableFeatures,
  useTable,
} from "@tanstack/react-table";
import type { ReactNode } from "react";
import { Link, useNavigate } from "react-router";
import { useMediaQuery } from "../../hooks/use-media-query";
import { useI18n } from "../../i18n";
import { cn } from "../../lib/cn";
import { Icon } from "./icons";

// Core-only table: search and pagination happen on the server, so no row-model features.
export const features = tableFeatures({});
export type Features = typeof features;
export const columnHelper = <T extends RowData>() => createColumnHelper<Features, T>();

/**
 * Design component 2, Table: sheet card radius 20, horizontal scroll (min 1040), header 13/500 ink2,
 * rows 60 tall with a track divider. With `rowHref` a whole row is one link (hover canvas +
 * underlined lead text, arrow at the end). Below 768px rows render as cards (`renderCard`) with a
 * track ring: canvas alone is nearly the sheet's color in light mode.
 */
export type TableSort = { id: string; dir: "asc" | "desc" };

/**
 * `sort` marks the sorted column (ink + arrow + aria-sort); columns in `sortable` get a header
 * button that calls `onSort(id)` (the page decides the direction: same column flips it).
 */
export function DataTable<T extends RowData>({
  columns,
  data,
  label,
  rowHref,
  numeric = [],
  sort,
  sortable = [],
  onSort,
  renderCard,
  footer,
  minWidth = 1040,
}: {
  columns: ColumnDef<Features, T, any>[];
  data: T[];
  label: string;
  rowHref?: (row: T) => string;
  numeric?: string[];
  sort?: TableSort | null;
  sortable?: string[];
  onSort?: (id: string) => void;
  renderCard?: (row: T) => ReactNode;
  footer?: ReactNode;
  minWidth?: number;
}) {
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
                <Link
                  to={rowHref(row)}
                  className="block rounded-row bg-canvas p-4 text-ink no-underline shadow-[inset_0_0_0_1px_var(--c-track)] hover:bg-muted"
                >
                  {renderCard(row)}
                </Link>
              ) : (
                <div className="rounded-row bg-canvas p-4 shadow-[inset_0_0_0_1px_var(--c-track)]">
                  {renderCard(row)}
                </div>
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
      <div className="relative overflow-x-auto">
        <table aria-label={label} className="w-full border-collapse" style={{ minWidth }}>
          <thead>
            {table.getHeaderGroups().map((group) => (
              <tr key={group.id}>
                {group.headers.map((header, i) => {
                  const id = header.column.id;
                  const active = sort?.id === id;
                  const arrow = active && (
                    <Icon
                      name={sort.dir === "asc" ? "up" : "down"}
                      size={14}
                      className="inline align-[-2px]"
                    />
                  );
                  return (
                    <th
                      key={header.id}
                      scope="col"
                      aria-sort={
                        active ? (sort.dir === "asc" ? "ascending" : "descending") : undefined
                      }
                      className={cn(
                        "border-b border-track py-3 text-caption font-medium whitespace-nowrap",
                        active ? "text-ink" : "text-ink2",
                        numeric.includes(id) ? "text-right" : "text-left",
                        i === 0 ? "pr-3 pl-6" : "px-3",
                      )}
                    >
                      {sortable.includes(id) && onSort ? (
                        <button
                          type="button"
                          onClick={() => onSort(id)}
                          className={cn(
                            "group/sort -mx-2 inline-flex items-center gap-1 rounded-full px-2 py-1 font-medium hover:bg-muted",
                            numeric.includes(id) && "flex-row-reverse",
                          )}
                        >
                          <table.FlexRender header={header} />
                          {arrow || (
                            <Icon
                              name="sort"
                              size={14}
                              className="opacity-0 group-hover/sort:opacity-60"
                            />
                          )}
                        </button>
                      ) : (
                        <>
                          {header.isPlaceholder ? null : <table.FlexRender header={header} />}
                          {arrow && <span className="ml-1">{arrow}</span>}
                        </>
                      )}
                    </th>
                  );
                })}
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
                <tr
                  key={row.id}
                  onClick={href ? () => void navigate(href) : undefined}
                  className={cn("group", href && "cursor-pointer hover:bg-canvas")}
                >
                  {row.getAllCells().map((cell, i) => (
                    <td
                      key={cell.id}
                      className={cn(
                        "h-[60px] border-b border-track py-2.5 text-body",
                        numeric.includes(cell.column.id) ? "text-right tabular-nums" : "text-left",
                        i === 0 ? "pr-3 pl-6" : "px-3",
                      )}
                    >
                      {i === 0 && href ? (
                        <Link
                          to={href}
                          className="text-ink no-underline group-hover:[&_.lead]:underline"
                          onClick={(e) => e.stopPropagation()}
                        >
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

export type SkeletonColumn = {
  header: string;
  align?: "left" | "right";
  sorted?: boolean;
  srOnly?: boolean;
  cell: (row: number) => ReactNode;
};

/**
 * Loading state of a DataTable (design component 2, State; board 13): the real frame stays (column
 * headers, sort mark, open column) and only the values are sand blocks. Below 768px it renders
 * `card` rows like DataTable does, so the phone doesn't get a 1040px skeleton.
 */
export function TableSkeleton({
  label,
  columns,
  card,
  rows = 8,
  rowLink,
  minWidth = 1040,
}: {
  label: string;
  columns: SkeletonColumn[];
  card: ReactNode;
  rows?: number;
  rowLink?: boolean;
  minWidth?: number;
}) {
  const narrow = useMediaQuery("(max-width: 767px)");
  const { t } = useI18n();
  const list = Array.from({ length: rows }, (_, r) => r);

  if (narrow) {
    return (
      <ul aria-busy="true" aria-label={label} className="m-0 flex list-none flex-col gap-2 p-3">
        {list.map((r) => (
          <li key={r} className="rounded-row bg-canvas p-4 shadow-[inset_0_0_0_1px_var(--c-track)]">
            {card}
          </li>
        ))}
      </ul>
    );
  }

  return (
    <div aria-busy="true" aria-label={label} className="overflow-x-auto">
      <table className="w-full border-collapse" style={{ minWidth }}>
        <thead>
          <tr>
            {columns.map((c, i) => (
              <th
                key={c.header}
                scope="col"
                aria-sort={c.sorted ? "descending" : undefined}
                className={cn(
                  "border-b border-track py-3 text-caption font-medium whitespace-nowrap",
                  c.sorted ? "text-ink" : "text-ink2",
                  c.align === "right" ? "text-right" : "text-left",
                  i === 0 ? "pr-3 pl-6" : "px-3",
                )}
              >
                {c.srOnly ? <span className="sr-only">{c.header}</span> : c.header}
                {c.sorted && <Icon name="down" size={14} className="ml-1 inline align-[-2px]" />}
              </th>
            ))}
            {rowLink && (
              <th scope="col" className="w-5 border-b border-track py-3 pr-6 pl-1">
                <span className="sr-only">{t.common.open}</span>
              </th>
            )}
          </tr>
        </thead>
        <tbody>
          {list.map((r) => (
            <tr key={r}>
              {columns.map((c, i) => (
                <td
                  key={c.header}
                  className={cn(
                    "h-[60px] border-b border-track py-2.5",
                    i === 0 ? "pr-3 pl-6" : "px-3",
                    c.align === "right" && "[&>*]:ml-auto",
                  )}
                >
                  {c.cell(r)}
                </td>
              ))}
              {rowLink && <td className="border-b border-track pr-6 pl-1" />}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
