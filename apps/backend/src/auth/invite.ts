import { and, eq, isNull } from "drizzle-orm";
import type { Db } from "../db/client";
import { inviteCodes } from "../db/schema";

export const INVITE_HEADER = "x-invite-code";

/**
 * Format kode `LUMA-XXXX`. Huruf besar/kecil gak ngaruh dan strip boleh
 * dilewatin (board Akun 06): `luma7q2k` → `LUMA-7Q2K`.
 */
export function normalizeInviteCode(code: string) {
  const compact = code.toUpperCase().replace(/[^A-Z0-9]/g, "");
  return compact.startsWith("LUMA") && compact.length > 4
    ? `LUMA-${compact.slice(4)}`
    : compact;
}

export type InviteResult = "ok" | "invalid" | "used";

/**
 * Pakai kode undangan secara atomik: satu UPDATE yang cuma berhasil kalau kode
 * ada dan belum dipakai, jadi dua sign-up bersamaan gak bisa makai kode yang sama.
 * Gagal → satu query lagi buat bedain "salah" vs "udah dipakai".
 */
export async function consumeInviteCode(db: Db, code: string, now = new Date()): Promise<InviteResult> {
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
