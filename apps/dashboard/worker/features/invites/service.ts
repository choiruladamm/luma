import { newInviteCode, normalizeInviteCode } from "../../../../backend/src/auth/invite";
import type { Db } from "../../../../backend/src/db/client";
import { ApiError } from "../../lib/errors";
import { deleteUnusedInvite, type InviteListQuery, insertInvites, inviteExists, listInvites } from "./repo";

/** Stored `LUMA-XXXXXXXXXX` → `LUMA-XXXXX-XXXXX` as handed out (same as `make backend-invite`); old short codes stay as is. */
export const displayInviteCode = (stored: string) =>
  /^LUMA-[A-Z0-9]{10}$/.test(stored) ? `${stored.slice(0, 10)}-${stored.slice(10)}` : stored;

export const INVITES_PAGE_SIZE = 20;

/** Invite list page: 1 batch (rows + counts). A page past the end returns no items (the client clamps). */
export async function getInvites(db: Db, query: Omit<InviteListQuery, "now">) {
  const { rows, counts } = await listInvites(db, { ...query, q: query.q || undefined, now: Date.now() });
  return {
    items: rows.map((r) => ({
      code: displayInviteCode(r.code),
      createdAt: r.createdAt?.toISOString() ?? null,
      usedBy: r.userId && r.email ? { id: r.userId, email: r.email } : null,
      usedAt: r.usedAt?.toISOString() ?? null,
    })),
    total: counts.total,
    page: query.page,
    pageCount: Math.max(1, Math.ceil(counts.total / query.limit)),
    counts: { all: counts.all, unused: counts.unused, used: counts.used },
  };
}

/** Create `count` codes in 1 insert. Stored normalized, returned in the hand-out format with the stored `createdAt`. */
export async function createInvites(db: Db, count: number) {
  const codes = Array.from({ length: count }, newInviteCode);
  const createdAt = new Date();
  await insertInvites(db, codes.map(normalizeInviteCode), createdAt);
  return { codes, createdAt: createdAt.toISOString() };
}

/** Delete an unused code: 1 query, +1 to tell 409 (used) from 404 (missing) when nothing was deleted. */
export async function deleteInvite(db: Db, code: string) {
  const normalized = normalizeInviteCode(code);
  if (await deleteUnusedInvite(db, normalized)) return normalized;
  if (await inviteExists(db, normalized)) throw new ApiError(409, "INVITE_CODE_USED", "Invite code has already been used");
  throw new ApiError(404, "NOT_FOUND", "Invite code not found");
}
