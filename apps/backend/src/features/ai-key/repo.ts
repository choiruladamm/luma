import { eq } from "drizzle-orm";
import type { Db } from "../../db/client";
import { aiKeys, users } from "../../db/schema";

export type AiKeyRow = typeof aiKeys.$inferSelect;
export type AiKeyValues = Omit<typeof aiKeys.$inferInsert, "userId">;

/** Satu query: status banned + key tersimpan (null kalau belum pernah dibuat). */
export async function findUserKey(db: Db, userId: string) {
  const [found] = await db
    .select({ banned: users.banned, key: aiKeys })
    .from(users)
    .leftJoin(aiKeys, eq(aiKeys.userId, users.id))
    .where(eq(users.id, userId));
  return { banned: found?.banned ?? false, key: found?.key ?? null };
}

export const setKeyLimit = (db: Db, userId: string, limitUsd: number) =>
  db.update(aiKeys).set({ limitUsd }).where(eq(aiKeys.userId, userId));

export const saveKey = (db: Db, userId: string, values: AiKeyValues) =>
  db
    .insert(aiKeys)
    .values({ userId, ...values })
    .onConflictDoUpdate({ target: aiKeys.userId, set: values });

export async function findKeyHash(db: Db, userId: string) {
  const [row] = await db.select({ keyHash: aiKeys.keyHash }).from(aiKeys).where(eq(aiKeys.userId, userId));
  return row?.keyHash ?? null;
}
