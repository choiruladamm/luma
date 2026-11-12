import { and, eq, isNull } from "drizzle-orm";
import type { Db } from "../db/client";
import { inviteCodes } from "../db/schema";

export const INVITE_HEADER = "x-invite-code";

const normalize = (code: string) => code.trim().toUpperCase();

/**
 * Pakai kode undangan secara atomik: cuma berhasil kalau kode ada dan belum dipakai.
 * Satu UPDATE, jadi dua sign-up bersamaan gak bisa makai kode yang sama.
 */
export async function consumeInviteCode(db: Db, code: string, now = new Date()) {
  const rows = await db
    .update(inviteCodes)
    .set({ usedAt: now })
    .where(and(eq(inviteCodes.code, normalize(code)), isNull(inviteCodes.usedAt)))
    .returning({ code: inviteCodes.code });
  return rows.length === 1;
}

export async function assignInviteCode(db: Db, code: string, userId: string) {
  await db
    .update(inviteCodes)
    .set({ usedBy: userId })
    .where(eq(inviteCodes.code, normalize(code)));
}
