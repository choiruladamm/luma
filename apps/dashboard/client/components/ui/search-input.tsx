import { forwardRef, type InputHTMLAttributes } from "react";
import { useI18n } from "../../i18n";
import { cn } from "../../lib/cn";
import { Icon } from "./icons";

/** Pill search field, height 44, icon left; optional clear button (cari kosong state). */
export const SearchInput = forwardRef<HTMLInputElement, { label: string; onClear?: () => void; tone?: "sheet" | "canvas" } & InputHTMLAttributes<HTMLInputElement>>(
  function SearchInput({ label, onClear, tone = "sheet", className, id, ...props }, ref) {
    const { t } = useI18n();
    const inputId = id ?? `search-${label.replace(/\s+/g, "-").toLowerCase()}`;
    return (
      <div className={cn("relative", className)}>
        <label htmlFor={inputId} className="sr-only">
          {label}
        </label>
        <Icon name="search" className="pointer-events-none absolute top-1/2 left-4 -translate-y-1/2 text-ink2" />
        <input
          ref={ref}
          id={inputId}
          type="search"
          autoComplete="off"
          className={cn("h-11 w-full rounded-full border-0 pr-4 pl-11 text-body text-ink [&::-webkit-search-cancel-button]:hidden", tone === "sheet" ? "bg-sheet" : "bg-canvas", onClear && props.value ? "pr-12" : "")}
          {...props}
        />
        {onClear && props.value ? (
          <button type="button" aria-label={t.common.clearSearch} onClick={onClear} className="absolute top-1/2 right-1 flex size-9 -translate-y-1/2 items-center justify-center rounded-full text-ink2 hover:bg-muted">
            <Icon name="x" size={16} />
          </button>
        ) : null}
      </div>
    );
  },
);
