import { and, eq, isNull } from "drizzle-orm";
import type { Db } from "../db/client";
import { inviteCodes } from "../db/schema";

export const INVITE_HEADER = "x-invite-code";

/**
 * Normalizes to the `LUMA-XXXX` format. Case and dashes don't matter
 * (board Akun 06): `luma7q2k` → `LUMA-7Q2K`.
 */
export function normalizeInviteCode(code: string) {
  const compact = code.toUpperCase().replace(/[^A-Z0-9]/g, "");
  return compact.startsWith("LUMA") && compact.length > 4 ? `LUMA-${compact.slice(4)}` : compact;
}

/** 32 letters/digits without lookalikes (0/O, 1/I): 5 bits per character, no modulo bias. */
const INVITE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";

/**
 * Generates a new invite code `LUMA-XXXXX-XXXXX`: 10 random characters = 32^10 ≈ 10^15
 * possibilities, which can't be brute-forced even if the per-IP rate limit is
 * bypassed (the old `LUMA-XXXX` format had only ≈10^6). Stored in the
 * [normalizeInviteCode] form.
 */
export function newInviteCode() {
  const chars = [...crypto.getRandomValues(new Uint8Array(10))]
    .map((b) => INVITE_ALPHABET[b & 31])
    .join("");
  return `LUMA-${chars.slice(0, 5)}-${chars.slice(5)}`;
}

export type InviteResult = "ok" | "invalid" | "used";

/**
 * Redeems an invite code atomically: one UPDATE that succeeds only if the code exists
 * and is unused, so two concurrent sign-ups can't use the same code.
 * On failure, one more query tells "wrong code" apart from "already used".
 */
export async function consumeInviteCode(
  db: Db,
  code: string,
  now = new Date(),
): Promise<InviteResult> {
  const normalized = normalizeInviteCode(code);
  const rows = await db
    .update(inviteCodes)
    .set({ usedAt: now })
    .where(and(eq(inviteCodes.code, normalized), isNull(inviteCodes.usedAt)))
    .returning({ code: inviteCodes.code });
  if (rows.length === 1) return "ok";
  const [existing] = await db
    .select({ code: inviteCodes.code })
    .from(inviteCodes)
    .where(eq(inviteCodes.code, normalized));
  return existing ? "used" : "invalid";
}

export async function assignInviteCode(db: Db, code: string, userId: string) {
  await db
    .update(inviteCodes)
    .set({ usedBy: userId })
    .where(eq(inviteCodes.code, normalizeInviteCode(code)));
}
