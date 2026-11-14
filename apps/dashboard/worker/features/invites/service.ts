import { newInviteCode, normalizeInviteCode } from "../../../../backend/src/auth/invite";
import type { Db } from "../../../../backend/src/db/client";
import { ApiError } from "../../lib/errors";
import { deleteUnusedInvite, insertInvites, inviteExists, listInvites } from "./repo";

/** Stored `LUMA-XXXXXXXXXX` → `LUMA-XXXXX-XXXXX` as handed out (same as `make backend-invite`); old short codes stay as is. */
export const displayInviteCode = (stored: string) =>
  /^LUMA-[A-Z0-9]{10}$/.test(stored) ? `${stored.slice(0, 10)}-${stored.slice(10)}` : stored;

/** Invite list, 1 query. */
export async function getInvites(db: Db, status?: "unused" | "used") {
  const rows = await listInvites(db, status);
  return {
    items: rows.map((r) => ({
      code: displayInviteCode(r.code),
      usedBy: r.userId && r.email ? { id: r.userId, email: r.email } : null,
      usedAt: r.usedAt?.toISOString() ?? null,
    })),
  };
}

/** Create `count` codes in 1 insert. Stored normalized, returned in the hand-out format. */
export async function createInvites(db: Db, count: number) {
  const codes = Array.from({ length: count }, newInviteCode);
  await insertInvites(db, codes.map(normalizeInviteCode));
  return { codes };
}

/** Delete an unused code: 1 query, +1 to tell 409 (used) from 404 (missing) when nothing was deleted. */
export async function deleteInvite(db: Db, code: string) {
  const normalized = normalizeInviteCode(code);
  if (await deleteUnusedInvite(db, normalized)) return normalized;
  if (await inviteExists(db, normalized)) throw new ApiError(409, "INVITE_CODE_USED", "Invite code has already been used");
  throw new ApiError(404, "NOT_FOUND", "Invite code not found");
}
