import { useSearchParams } from "react-router";

export type UserSort = "created" | "lastActive" | "r2" | "sync" | "relevance";
export type UsersParams = {
  q: string;
  status?: "active" | "banned";
  ai?: "yes" | "no";
  activity?: "7d" | "30d" | "never";
  /** Unset = the worker's default: relevance with `q`, newest without. */
  sort?: UserSort;
  dir: "asc" | "desc";
  page: number;
  limit: 25 | 50;
};

export const DEFAULT_USERS_PARAMS: UsersParams = { q: "", dir: "desc", page: 1, limit: 50 };

const pick = <T extends string>(value: string | null, allowed: readonly T[]) =>
  allowed.includes(value as T) ? (value as T) : undefined;

/** URL → params. Unknown values fall back to the defaults instead of failing the screen. */
export function parseUsersParams(search: URLSearchParams): UsersParams {
  const page = Number(search.get("page"));
  return {
    q: (search.get("q") ?? "").trim(),
    status: pick(search.get("status"), ["active", "banned"] as const),
    ai: pick(search.get("ai"), ["yes", "no"] as const),
    activity: pick(search.get("activity"), ["7d", "30d", "never"] as const),
    sort: pick(search.get("sort"), ["created", "lastActive", "r2", "sync", "relevance"] as const),
    dir: search.get("dir") === "asc" ? "asc" : "desc",
    page: Number.isInteger(page) && page > 1 ? page : 1,
    limit: search.get("limit") === "25" ? 25 : 50,
  };
}

/**
 * Params → the non-default entries, in a fixed order. Used for the URL, the API query, and the
 * query key, so the header search (page 1, q only) and the Users page share one cache entry.
 */
export function usersSearchEntries(p: UsersParams): Record<string, string> {
  const out: Record<string, string> = {};
  if (p.q) out.q = p.q;
  if (p.status) out.status = p.status;
  if (p.ai) out.ai = p.ai;
  if (p.activity) out.activity = p.activity;
  if (p.sort) out.sort = p.sort;
  if (p.dir !== "desc") out.dir = p.dir;
  if (p.page > 1) out.page = String(p.page);
  if (p.limit !== 50) out.limit = String(p.limit);
  return out;
}

/** How many filters (not search or sort) are on, for the phone "Filter" badge and Reset. */
export const activeFilterCount = (p: UsersParams) =>
  [p.status, p.ai, p.activity].filter(Boolean).length;

/**
 * The Users list state lives in the URL (reload, back, and shared links keep it). `set` merges a
 * patch; anything but a page change goes back to page 1.
 */
export function useUsersParams() {
  const [search, setSearch] = useSearchParams();
  const params = parseUsersParams(search);
  const set = (patch: Partial<UsersParams>) => {
    const next = { ...params, ...patch, page: patch.page ?? 1 };
    // No router scroll reset: the table stays in view (Pagination scrolls to its top smoothly).
    setSearch(usersSearchEntries(next), {
      replace: patch.page === undefined,
      preventScrollReset: true,
    });
  };
  return { params, set };
}
