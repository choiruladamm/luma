import { useState } from "react";
import { Button } from "../../../components/ui/button";
import { Dialog } from "../../../components/ui/dialog";
import { Icon } from "../../../components/ui/icons";
import { Segmented } from "../../../components/ui/segmented";
import { useI18n } from "../../../i18n";
import { cn } from "../../../lib/cn";
import { activeFilterCount, type UserSort, type UsersParams } from "../hooks/use-users-params";

type SetParams = (patch: Partial<UsersParams>) => void;

/** A native select dressed as a chip: the platform picker on phones, full keyboard support. */
/** Ink when it differs from the default (`active`, or a non-empty value for filters). */
function SelectChip({ label, value, onChange, options, block, active }: { label: string; value: string; onChange: (v: string) => void; options: [string, string][]; block?: boolean; active?: boolean }) {
  const on = active ?? value !== "";
  return (
    <label className={cn("relative inline-flex h-10 items-center gap-1.5 rounded-full pr-8 pl-3.5 text-caption font-medium", on ? "bg-ink text-canvas" : "bg-muted text-ink", block && "h-12 w-full justify-between text-body")}>
      <span className={on ? "text-canvas/70" : "text-ink2"}>{label}</span>
      <span className="truncate">{options.find(([v]) => v === value)?.[1]}</span>
      <select value={value} onChange={(e) => onChange(e.target.value)} className="absolute inset-0 cursor-pointer appearance-none opacity-0" aria-label={label}>
        {options.map(([v, text]) => (
          <option key={v} value={v}>
            {text}
          </option>
        ))}
      </select>
      <Icon name="chevdown" size={14} className="pointer-events-none absolute right-3" />
    </label>
  );
}

function FilterFields({ params, set, block }: { params: UsersParams; set: SetParams; block?: boolean }) {
  const { t } = useI18n();
  return (
    <>
      <SelectChip
        block={block}
        label={t.users.status}
        value={params.status ?? ""}
        onChange={(v) => set({ status: (v || undefined) as UsersParams["status"] })}
        options={[["", t.users.any], ["active", t.users.active], ["banned", t.users.banned]]}
      />
      <SelectChip
        block={block}
        label={t.users.aiKey}
        value={params.ai ?? ""}
        onChange={(v) => set({ ai: (v || undefined) as UsersParams["ai"] })}
        options={[["", t.users.any], ["yes", t.users.aiYes], ["no", t.users.aiNo]]}
      />
      <SelectChip
        block={block}
        label={t.users.activity}
        value={params.activity ?? ""}
        onChange={(v) => set({ activity: (v || undefined) as UsersParams["activity"] })}
        options={[["", t.users.any], ["7d", t.users.active7d], ["30d", t.users.active30d], ["never", t.users.neverActive]]}
      />
    </>
  );
}

/** Desktop: filter chips in the toolbar, plus Reset once any is on. Sorting is on the column headers. */
export function UsersFilterChips({ params, set }: { params: UsersParams; set: SetParams }) {
  const { t } = useI18n();
  return (
    <div className="flex flex-wrap items-center gap-2">
      <FilterFields params={params} set={set} />
      {activeFilterCount(params) > 0 && (
        <button type="button" onClick={() => set({ status: undefined, ai: undefined, activity: undefined })} className="h-10 rounded-full px-3 text-caption font-medium text-ink2 hover:bg-muted hover:text-ink">
          {t.users.reset}
        </button>
      )}
    </div>
  );
}

/** Phone: one "Filter" button (with the count of active filters) opening a sheet with filters and sort. */
export function UsersFilterSheet({ params, set, currentSort }: { params: UsersParams; set: SetParams; currentSort: UserSort }) {
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
      <Button variant="secondary" icon="filter" onClick={() => setOpen(true)} className="md:hidden">
        {t.users.filter}
        {count > 0 && <span className="rounded-full bg-ink px-2 text-chip leading-5 font-semibold text-canvas tabular-nums">{count}</span>}
      </Button>
      <Dialog
        open={open}
        onClose={() => setOpen(false)}
        title={t.users.filters}
        icon="filter"
        footer={
          <div className="grid grid-cols-2 gap-2.5 px-6 pt-5 pb-6">
            <Button variant="secondary" size="lg" onClick={() => set({ status: undefined, ai: undefined, activity: undefined, sort: undefined, dir: "desc" })}>
              {t.users.reset}
            </Button>
            <Button variant="primary" size="lg" onClick={() => setOpen(false)}>
              {t.users.done}
            </Button>
          </div>
        }
      >
        <div className="flex flex-col gap-2.5">
          <FilterFields params={params} set={set} block />
        </div>
        <div className="flex flex-col gap-2.5">
          <SelectChip block active={params.sort !== undefined} label={t.users.sortLabel} value={currentSort} onChange={(v) => set({ sort: v as UserSort })} options={sorts} />
          {currentSort !== "relevance" && (
            <Segmented
              label={t.users.sortLabel}
              kind="radio"
              stretch
              value={params.dir}
              onChange={(dir) => set({ dir })}
              options={[
                { value: "desc", label: currentSort === "created" ? t.users.newestFirst : t.users.descending },
                { value: "asc", label: currentSort === "created" ? t.users.oldestFirst : t.users.ascending },
              ]}
            />
          )}
        </div>
      </Dialog>
    </>
  );
}
