import { useCallback } from "react";
import { useSearchParams } from "react-router";
import { useSearchWriter } from "../../../hooks/use-search-writer";

export type InviteSort = "default" | "createdAt" | "usedAt" | "code";
export type InvitesParams = {
  q: string;
  status?: "unused" | "used";
  /** Only codes used within the window (so it goes with status "used"). */
  used_within?: "7d" | "30d";
  sort: InviteSort;
  dir: "asc" | "desc";
  page: number;
  limit: 20 | 50;
};

export const DEFAULT_INVITES_PARAMS: InvitesParams = {
  q: "",
  sort: "default",
  dir: "desc",
  page: 1,
  limit: 20,
};

const pick = <T extends string>(value: string | null, allowed: readonly T[]) =>
  allowed.find((a) => a === value);

/** URL → params. Unknown values fall back to the defaults instead of failing the screen. */
export function parseInvitesParams(search: URLSearchParams): InvitesParams {
  const page = Number(search.get("page"));
  return {
    q: (search.get("q") ?? "").trim(),
    status: pick(search.get("status"), ["unused", "used"] as const),
    // Bookmarks from before the API went snake_case carry `usedWithin`.
    used_within: pick(search.get("used_within") ?? search.get("usedWithin"), [
      "7d",
      "30d",
    ] as const),
    sort:
      pick(search.get("sort"), ["default", "createdAt", "usedAt", "code"] as const) ?? "default",
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
  if (p.used_within) out.used_within = p.used_within;
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
  const [search] = useSearchParams();
  const params = parseInvitesParams(search);
  const write = useSearchWriter();
  const set = useCallback(
    (patch: Partial<InvitesParams>) =>
      write(
        (prev) => {
          const next = { ...parseInvitesParams(prev), ...patch, page: patch.page ?? 1 };
          if (patch.used_within) next.status = "used";
          if ("status" in patch && patch.status !== "used" && !("used_within" in patch))
            next.used_within = undefined;
          return invitesSearchEntries(next);
        },
        // No router scroll reset: the table stays in view (Pagination scrolls to its top smoothly).
        { replace: patch.page === undefined, preventScrollReset: true },
      ),
    [write],
  );
  return { params, set };
}
