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

/** 32 huruf/angka tanpa yang mirip (0/O, 1/I): 5 bit per karakter, tanpa bias modulo. */
const INVITE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";

/**
 * Kode undangan baru `LUMA-XXXXX-XXXXX`: 10 karakter acak = 32^10 ≈ 10^15
 * kemungkinan, gak bisa ditebak lewat brute force walau rate limit per IP
 * diakalin (format lama `LUMA-XXXX` cuma ±10^6). Disimpan dalam bentuk
 * [normalizeInviteCode].
 */
export function newInviteCode() {
  const chars = [...crypto.getRandomValues(new Uint8Array(10))].map((b) => INVITE_ALPHABET[b & 31]).join("");
  return `LUMA-${chars.slice(0, 5)}-${chars.slice(5)}`;
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
