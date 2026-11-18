import { useEffect, useRef, useState } from "react";
import { Button, IconButton } from "../../../components/ui/button";
import { Dialog } from "../../../components/ui/dialog";
import { Icon } from "../../../components/ui/icons";
import { Segmented } from "../../../components/ui/segmented";
import { Select } from "../../../components/ui/select";
import { useI18n } from "../../../i18n";
import { cn } from "../../../lib/cn";
import { activeFilterCount, type UserSort, type UsersParams } from "../hooks/use-users-params";

type SetParams = (patch: Partial<UsersParams>) => void;

type FilterKey = "status" | "ai" | "activity";
const CLEARED = {
  status: undefined,
  ai: undefined,
  activity: undefined,
} satisfies Partial<UsersParams>;

/** Every filter once: label + options. New filters go here and show up in the panel, sheet, and chips. */
function useFilters() {
  const { t } = useI18n();
  const defs: { key: FilterKey; label: string; options: [string, string][] }[] = [
    {
      key: "status",
      label: t.users.status,
      options: [
        ["", t.users.any],
        ["active", t.users.active],
        ["banned", t.users.banned],
      ],
    },
    {
      key: "ai",
      label: t.users.aiKey,
      options: [
        ["", t.users.any],
        ["yes", t.users.aiYes],
        ["no", t.users.aiNo],
      ],
    },
    {
      key: "activity",
      label: t.users.activity,
      options: [
        ["", t.users.any],
        ["7d", t.users.active7d],
        ["30d", t.users.active30d],
        ["never", t.users.neverActive],
      ],
    },
  ];
  return defs;
}

function FilterFields({ params, set }: { params: UsersParams; set: SetParams }) {
  return (
    <>
      {useFilters().map((f) => (
        <Select
          key={f.key}
          block
          label={f.label}
          value={params[f.key] ?? ""}
          options={f.options}
          active={!!params[f.key]}
          onChange={(v) => set({ [f.key]: v || undefined })}
        />
      ))}
    </>
  );
}

/** The filters that are on, as removable chips + "Reset", under the toolbar (desktop and phone). */
export function ActiveFilters({ params, set }: { params: UsersParams; set: SetParams }) {
  const { t } = useI18n();
  const on = useFilters().filter((f) => params[f.key]);
  if (on.length === 0) return null;
  return (
    <div className="flex flex-wrap items-center gap-2">
      {on.map((f) => {
        const text = f.options.find(([v]) => v === params[f.key])?.[1];
        return (
          <button
            key={f.key}
            type="button"
            aria-label={t.users.removeFilter(`${f.label}: ${text}`)}
            onClick={() => set({ [f.key]: undefined })}
            className="inline-flex h-8 items-center gap-1.5 rounded-full bg-ink pr-2 pl-3 text-caption font-medium text-canvas hover:opacity-90"
          >
            <span className="text-canvas/70">{f.label}</span>
            {text}
            <Icon name="x" size={14} />
          </button>
        );
      })}
      <button
        type="button"
        onClick={() => set(CLEARED)}
        className="h-8 rounded-full px-2.5 text-caption font-medium text-ink2 hover:bg-muted hover:text-ink"
      >
        {t.users.resetAll}
      </button>
    </div>
  );
}

/** Desktop filter button: a small panel with every filter, so the toolbar stays two controls wide. */
function FilterPopover({ params, set }: { params: UsersParams; set: SetParams }) {
  const { t } = useI18n();
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  const count = activeFilterCount(params);
  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) =>
      e.target instanceof Node && !root.current?.contains(e.target) && setOpen(false);
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && !e.defaultPrevented && setOpen(false);
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);
  return (
    <div ref={root} className="relative">
      <button
        type="button"
        aria-expanded={open}
        aria-haspopup="dialog"
        onClick={() => setOpen((o) => !o)}
        className={cn(
          "inline-flex h-10 items-center gap-2 rounded-full px-3.5 text-caption font-medium",
          count > 0 ? "bg-ink text-canvas" : "bg-muted text-ink hover:bg-track",
        )}
      >
        <Icon name="filter" size={16} />
        {t.users.filter}
        {count > 0 && (
          <span className="rounded-full bg-canvas px-1.5 text-[11px] leading-[18px] font-semibold text-ink tabular-nums">
            {count}
          </span>
        )}
      </button>
      {open && (
        <div
          role="dialog"
          aria-label={t.users.filters}
          className="absolute top-[calc(100%+6px)] right-0 z-30 flex w-[300px] flex-col gap-2.5 rounded-menu bg-sheet p-3 shadow-[var(--shadow-sheet),inset_0_0_0_1px_var(--c-track)]"
        >
          <FilterFields params={params} set={set} />
          {count > 0 && (
            <button
              type="button"
              onClick={() => set(CLEARED)}
              className="h-10 rounded-full text-caption font-medium text-ink2 hover:bg-muted hover:text-ink"
            >
              {t.users.resetAll}
            </button>
          )}
        </div>
      )}
    </div>
  );
}

/**
 * Desktop toolbar: a Filter button (panel with every filter) and a Sort chip (sort + direction in
 * one pick, so "oldest first" is one click away; the column headers sort too).
 */
export function UsersFilterChips({
  params,
  set,
  currentSort,
}: {
  params: UsersParams;
  set: SetParams;
  currentSort: UserSort;
}) {
  const { t } = useI18n();
  const column: Record<UserSort, string> = {
    relevance: t.users.relevance,
    created: t.users.joined,
    lastActive: t.users.lastActive,
    r2: t.users.files,
    sync: t.users.syncData,
  };
  const sorts: [string, string][] = [
    ...(params.q ? ([["relevance:desc", t.users.relevance]] as [string, string][]) : []),
    ["created:desc", t.users.sortNewest],
    ["created:asc", t.users.sortOldest],
    ["lastActive:desc", t.users.sortRecentActive],
    ["r2:desc", t.users.sortBiggestFiles],
    ["sync:desc", t.users.sortBiggestSync],
  ];
  const value = `${currentSort}:${currentSort === "relevance" ? "desc" : params.dir}`;
  // A direction picked from a column header that the list doesn't name still shows as chosen.
  if (!sorts.some(([v]) => v === value))
    sorts.push([
      value,
      t.users.sortCustom(
        column[currentSort],
        params.dir === "asc" ? t.users.ascending : t.users.descending,
      ),
    ]);
  return (
    <div className="flex items-center gap-2">
      <FilterPopover params={params} set={set} />
      <Select
        label={t.users.sortLabel}
        value={value}
        options={sorts}
        active={params.sort !== undefined}
        onChange={(v) => {
          // oxlint-disable-next-line typescript/no-unsafe-type-assertion -- the value comes from this select's own options
          const [sort, dir] = v.split(":") as [UserSort, "asc" | "desc"];
          set({ sort, dir });
        }}
      />
    </div>
  );
}

/** Phone: one "Filter" button (with the count of active filters) opening a sheet with filters and sort. */
export function UsersFilterSheet({
  params,
  set,
  currentSort,
}: {
  params: UsersParams;
  set: SetParams;
  currentSort: UserSort;
}) {
  const { t } = useI18n();
  const [open, setOpen] = useState(false);
  const count = activeFilterCount(params);
  const sorts: [UserSort, string][] = [
    ...(params.q ? ([["relevance", t.users.relevance]] as [UserSort, string][]) : []),
    ["created", t.users.joined],
    ["lastActive", t.users.lastActive],
    ["r2", t.users.files],
    ["sync", t.users.syncData],
  ];
  return (
    <>
      {/* Icon button beside the search field (same 44 height); the badge counts active filters. */}
      <div className="relative flex-none md:hidden">
        <IconButton
          icon="filter"
          label={count > 0 ? `${t.users.filter} (${count})` : t.users.filter}
          variant={count > 0 ? "primary" : "secondary"}
          onClick={() => setOpen(true)}
        />
        {count > 0 && (
          <span
            aria-hidden="true"
            className="pointer-events-none absolute -top-1 -right-1 flex size-5 items-center justify-center rounded-full bg-ink text-[11px] font-semibold text-canvas tabular-nums shadow-[0_0_0_2px_var(--c-sheet)]"
          >
            {count}
          </span>
        )}
      </div>
      <Dialog
        open={open}
        onClose={() => setOpen(false)}
        title={t.users.filters}
        icon="filter"
        footer={
          <div className="grid grid-cols-2 gap-2.5 px-6 pt-5 pb-6">
            <Button
              variant="secondary"
              size="lg"
              onClick={() => set({ ...CLEARED, sort: undefined, dir: "desc" })}
            >
              {t.users.reset}
            </Button>
            <Button variant="primary" size="lg" onClick={() => setOpen(false)}>
              {t.users.done}
            </Button>
          </div>
        }
      >
        <div className="flex flex-col gap-2.5">
          <FilterFields params={params} set={set} />
        </div>
        <div className="flex flex-col gap-2.5">
          <Select
            block
            active={params.sort !== undefined}
            label={t.users.sortLabel}
            value={currentSort}
            onChange={(v) => set({ sort: v })}
            options={sorts}
          />
          {currentSort !== "relevance" && (
            <Segmented
              label={t.users.sortLabel}
              kind="radio"
              stretch
              value={params.dir}
              onChange={(dir) => set({ dir })}
              options={[
                {
                  value: "desc",
                  label: currentSort === "created" ? t.users.newestFirst : t.users.descending,
                },
                {
                  value: "asc",
                  label: currentSort === "created" ? t.users.oldestFirst : t.users.ascending,
                },
              ]}
            />
          )}
        </div>
      </Dialog>
    </>
  );
}
