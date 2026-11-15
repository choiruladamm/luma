import { useSearchParams } from "react-router";

export type InviteSort = "default" | "usedAt" | "code";
export type InvitesParams = {
  q: string;
  status?: "unused" | "used";
  /** Only codes used within the window (so it goes with status "used"). */
  usedWithin?: "7d" | "30d";
  sort: InviteSort;
  dir: "asc" | "desc";
  page: number;
  limit: 20 | 50;
};

export const DEFAULT_INVITES_PARAMS: InvitesParams = { q: "", sort: "default", dir: "desc", page: 1, limit: 20 };

const pick = <T extends string>(value: string | null, allowed: readonly T[]) => (allowed.includes(value as T) ? (value as T) : undefined);

/** URL → params. Unknown values fall back to the defaults instead of failing the screen. */
export function parseInvitesParams(search: URLSearchParams): InvitesParams {
  const page = Number(search.get("page"));
  return {
    q: (search.get("q") ?? "").trim(),
    status: pick(search.get("status"), ["unused", "used"] as const),
    usedWithin: pick(search.get("usedWithin"), ["7d", "30d"] as const),
    sort: pick(search.get("sort"), ["default", "usedAt", "code"] as const) ?? "default",
    dir: search.get("dir") === "asc" ? "asc" : "desc",
    page: Number.isInteger(page) && page > 1 ? page : 1,
    limit: search.get("limit") === "50" ? 50 : 20,
  };
}

/** Params → the non-default entries: the URL, the API query, and the query key. */
export function invitesSearchEntries(p: InvitesParams): Record<string, string> {
  const out: Record<string, string> = {};
  if (p.q) out.q = p.q;
  if (p.status) out.status = p.status;
  if (p.usedWithin) out.usedWithin = p.usedWithin;
  if (p.sort !== "default") out.sort = p.sort;
  if (p.dir !== "desc") out.dir = p.dir;
  if (p.page > 1) out.page = String(p.page);
  if (p.limit !== 20) out.limit = String(p.limit);
  return out;
}

/**
 * The Invites list state lives in the URL. `set` merges a patch; anything but a page change goes
 * back to page 1. "Used within" only makes sense for used codes: picking it selects the Used tab,
 * and the Unused tab clears it.
 */
export function useInvitesParams() {
  const [search, setSearch] = useSearchParams();
  const params = parseInvitesParams(search);
  const set = (patch: Partial<InvitesParams>) => {
    const next = { ...params, ...patch, page: patch.page ?? 1 };
    if (patch.usedWithin) next.status = "used";
    if ("status" in patch && patch.status !== "used" && !("usedWithin" in patch)) next.usedWithin = undefined;
    // No router scroll reset: the table stays in view (Pagination scrolls to its top smoothly).
    setSearch(invitesSearchEntries(next), { replace: patch.page === undefined, preventScrollReset: true });
  };
  return { params, set };
}
