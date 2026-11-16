// Tabel `user_storage` dipakai bareng: kuota R2 (`bytes`, file buku + backup)
// dan cursor sync (`seq`, lihat features/sync/repo.ts).
import { eq, sql } from "drizzle-orm";
import { ApiError } from "../lib/errors";
import type { Db } from "./client";
import { userStorage } from "./schema";

export async function storedBytes(db: Db, userId: string): Promise<number> {
  const [row] = await db
    .select({ bytes: userStorage.bytes })
    .from(userStorage)
    .where(eq(userStorage.userId, userId));
  return row?.bytes ?? 0;
}

export const addBytes = (db: Db, userId: string, delta: number) =>
  db
    .insert(userStorage)
    .values({ userId, bytes: Math.max(0, delta) })
    .onConflictDoUpdate({
      target: userStorage.userId,
      set: { bytes: sql`max(0, ${userStorage.bytes} + ${delta})` },
    });

/**
 * Pesan [size] byte kuota sebelum upload, atomik: satu upsert yang cuma nambah
 * kalau `bytes + size ≤ quota`. Upload paralel gak bisa lolos cek bareng-bareng
 * lalu bareng-bareng lewat kuota. Gak muat → 413 STORAGE_FULL. Upload gagal →
 * kembalikan lewat `addBytes(db, userId, -size)`.
 */
export async function reserveBytes(db: Db, userId: string, size: number, quota: number) {
  const reserved =
    size <= quota &&
    (
      await db
        .insert(userStorage)
        .values({ userId, bytes: size })
        .onConflictDoUpdate({
          target: userStorage.userId,
          set: { bytes: sql`${userStorage.bytes} + ${size}` },
          setWhere: sql`${userStorage.bytes} + ${size} <= ${quota}`,
        })
        .returning({ bytes: userStorage.bytes })
    ).length === 1;
  if (!reserved) throw new ApiError(413, "STORAGE_FULL", "Cloud storage is full");
}

/** Jalanin [upload]; gagal → kuota yang udah dipesan dikembalikan, error dilempar ulang. */
export async function releaseOnFailure<T>(db: Db, userId: string, size: number, upload: () => Promise<T>) {
  try {
    return await upload();
  } catch (e) {
    await addBytes(db, userId, -size);
    throw e;
  }
}
