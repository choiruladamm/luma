// The `user_storage` table is shared: R2 quota (`bytes`, book files + backups)
// and the sync cursor (`seq`, see features/sync/repo.ts).
import { eq, sql } from "drizzle-orm";
import { ApiError } from "../lib/errors";
import type { Db } from "@luma/core/db/client";
import { userStorage } from "@luma/core/db/schema";

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

const storageFull = () => new ApiError(413, "STORAGE_FULL", "Cloud storage is full");

/**
 * Reserves [size] bytes of quota before an upload, atomically: one upsert that adds
 * only if `bytes + size ≤ quota`. Parallel uploads can't all pass the check and then
 * together exceed the quota. Doesn't fit → 413 STORAGE_FULL. Upload fails →
 * return it via `addBytes(db, userId, -size)`.
 */
export async function reserveBytes(db: Db, userId: string, size: number, quota: number) {
  if (size > quota) throw storageFull();
  const reserved = await db
    .insert(userStorage)
    .values({ userId, bytes: size })
    .onConflictDoUpdate({
      target: userStorage.userId,
      set: { bytes: sql`${userStorage.bytes} + ${size}` },
      setWhere: sql`${userStorage.bytes} + ${size} <= ${quota}`,
    })
    .returning({ bytes: userStorage.bytes });
  if (reserved.length !== 1) throw storageFull();
}

/** Runs [upload]; on failure the reserved quota is returned and the error is rethrown. */
export async function releaseOnFailure<T>(
  db: Db,
  userId: string,
  size: number,
  upload: () => Promise<T>,
) {
  try {
    return await upload();
  } catch (e) {
    await addBytes(db, userId, -size);
    throw e;
  }
}
