import { type KeyboardEvent, useEffect, useId, useRef, useState } from "react";
import { useNavigate } from "react-router";
import { Icon, Spinner } from "../../../components/ui/icons";
import { SearchInput } from "../../../components/ui/search-input";
import { Skeleton } from "../../../components/ui/skeleton";
import { useDebounce } from "../../../hooks/use-debounce";
import { useI18n } from "../../../i18n";
import { errorText } from "../../../lib/api-error";
import { cn } from "../../../lib/cn";
import { formatNumber } from "../../../lib/format";
import { useUsers } from "../queries/use-users";
import { UserIdentity, UserStatusChip } from "./user-columns";

const MIN = 2;
const MAX = 100; // same limit as the worker's `q`
const SHOWN = 5;

// Pasted "mailto:Name@Mail.com " → "name@mail.com"; the worker matches case-insensitively anyway.
const normalize = (v: string) => v.trim().toLowerCase().replace(/^mailto:/, "");

const typingInField = (el: EventTarget | null) =>
  el instanceof HTMLElement && (el.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName));

/**
 * Header email search (combobox): after a 300ms pause with ≥2 characters, the first 5 users by
 * email prefix, then "see all" → /users?q=. Same query as the Users page, so opening the full
 * list reuses the cache: one request per pause at most (free tier).
 */
export function QuickSearch({ shortcut, autoFocus, onDone, tone, className }: { shortcut?: boolean; autoFocus?: boolean; onDone?: () => void; tone?: "sheet" | "canvas"; className?: string }) {
  const { t, locale } = useI18n();
  const navigate = useNavigate();
  const listId = useId();
  // Own id: the desktop field and the phone search row can both be mounted (CSS shows one).
  const inputId = useId();
  const inputRef = useRef<HTMLInputElement>(null);
  const [value, setValue] = useState("");
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(-1);

  const typed = normalize(value);
  const q = useDebounce(typed, 300);
  const valid = q.length >= MIN && q.length <= MAX;
  const users = useUsers(q, valid);

  const page = valid ? users.data?.pages[0] : undefined;
  const items = page?.items.slice(0, SHOWN) ?? [];
  const settled = typed === q && valid;
  const loading = typed.length >= MIN && (!settled || users.isPending);
  const showList = open && typed.length >= MIN;
  // Options: the users, then "see all" (only once there is something to see).
  const count = items.length + (items.length > 0 ? 1 : 0);

  useEffect(() => setActive(-1), [q]);

  // "/" focuses the field from anywhere, unless the admin is typing somewhere else.
  useEffect(() => {
    if (!shortcut) return;
    const onKey = (e: globalThis.KeyboardEvent) => {
      if (e.key !== "/" || e.metaKey || e.ctrlKey || e.altKey || typingInField(e.target)) return;
      e.preventDefault();
      inputRef.current?.focus();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [shortcut]);

  const finish = (to: string) => {
    void navigate(to);
    setValue("");
    setOpen(false);
    inputRef.current?.blur();
    onDone?.();
  };
  const seeAll = () => finish(`/users?q=${encodeURIComponent(typed)}`);
  const choose = (index: number) => {
    if (index >= 0 && index < items.length) return finish(`/users/${items[index]!.id}`);
    // Enter on a full, exact email (ranked first by the worker) opens that user directly.
    if (index < 0 && settled && items[0]?.email.toLowerCase() === typed) return finish(`/users/${items[0].id}`);
    seeAll();
  };

  const onKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      setOpen(true);
      if (count === 0) return;
      setActive((i) => (e.key === "ArrowDown" ? (i + 1) % count : (i <= 0 ? count : i) - 1));
    } else if (e.key === "Enter") {
      e.preventDefault();
      if (typed.length >= MIN) choose(active);
    } else if (e.key === "Escape") {
      if (open && typed) setOpen(false);
      else {
        setValue("");
        onDone?.();
      }
    }
  };

  const optionId = (i: number) => `${listId}-${i}`;
  const total = page ? (page.nextCursor ? `${formatNumber(page.items.length, locale)}+` : formatNumber(page.items.length, locale)) : "";

  return (
    <div className={cn("relative", className)}>
      <SearchInput
        ref={inputRef}
        id={inputId}
        label={t.shell.searchUsers}
        placeholder={t.shell.searchUsersPlaceholder}
        tone={tone}
        value={value}
        autoFocus={autoFocus}
        maxLength={MAX}
        role="combobox"
        aria-expanded={showList}
        aria-controls={listId}
        aria-autocomplete="list"
        aria-activedescendant={showList && active >= 0 ? optionId(active) : undefined}
        onChange={(e) => {
          setValue(e.target.value);
          setOpen(true);
        }}
        onFocus={() => setOpen(true)}
        onBlur={() => setOpen(false)}
        onKeyDown={onKeyDown}
        className="[&_input]:pr-11"
      />
      <span aria-hidden="true" className="pointer-events-none absolute top-1/2 right-4 flex -translate-y-1/2 items-center text-ink2">
        {loading ? (
          <Spinner size={16} />
        ) : (
          shortcut &&
          !value && <kbd className="inline-flex h-[22px] items-center rounded-[7px] bg-muted px-[7px] font-mono text-chip font-medium text-ink shadow-[inset_0_-1px_0_var(--c-track)]">/</kbd>
        )}
      </span>
      {showList && (
        // mousedown keeps focus in the field, so the blur doesn't close the list before the click lands.
        <div onMouseDown={(e) => e.preventDefault()} className="absolute inset-x-0 top-[calc(100%+8px)] z-30 rounded-menu bg-sheet p-2 shadow-[var(--shadow-sheet),inset_0_0_0_1px_var(--c-track)]">
          <ul id={listId} role="listbox" aria-label={t.shell.searchResults} className="m-0 flex list-none flex-col gap-0.5 p-0">
            {users.isError && settled ? (
              <li className="px-3 py-3 text-body text-danger-ink">{errorText(users.error, t)}</li>
            ) : loading && items.length === 0 ? (
              [0, 1].map((i) => (
                <li key={i} aria-hidden="true" className="flex items-center gap-3 px-3 py-2">
                  <Skeleton className="size-9 flex-none" />
                  <span className="flex flex-1 flex-col gap-1.5">
                    <Skeleton className="h-3 w-40" />
                    <Skeleton className="h-2.5 w-24" />
                  </span>
                </li>
              ))
            ) : items.length === 0 ? (
              <li className="px-3 py-3 text-body text-ink2">{t.users.noMatch(typed)}</li>
            ) : (
              <>
                {items.map((u, i) => (
                  <li
                    key={u.id}
                    id={optionId(i)}
                    role="option"
                    aria-selected={active === i}
                    onMouseEnter={() => setActive(i)}
                    onClick={() => choose(i)}
                    className={cn("flex cursor-pointer items-center justify-between gap-3 rounded-row px-3 py-2", active === i && "bg-canvas")}
                  >
                    <UserIdentity user={u} q={typed} />
                    <UserStatusChip banned={u.banned} />
                  </li>
                ))}
                <li role="presentation" aria-hidden="true" className="mx-3 my-1 h-px bg-track" />
                <li
                  id={optionId(items.length)}
                  role="option"
                  aria-selected={active === items.length}
                  onMouseEnter={() => setActive(items.length)}
                  onClick={seeAll}
                  className={cn("flex min-h-11 cursor-pointer items-center justify-between gap-3 rounded-row px-3 text-body font-medium", active === items.length && "bg-canvas")}
                >
                  {t.shell.seeAllResults(total)}
                  <Icon name="arrow" size={16} />
                </li>
              </>
            )}
          </ul>
        </div>
      )}
    </div>
  );
}
