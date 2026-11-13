// Tabel `user_storage` dipakai bareng: kuota R2 (`bytes`, file buku + backup)
// dan cursor sync (`seq`, lihat features/sync/repo.ts).
import { eq, sql } from "drizzle-orm";
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
