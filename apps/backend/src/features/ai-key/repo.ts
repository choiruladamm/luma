import { eq } from "drizzle-orm";
import type { Db } from "@luma/core/db/client";
import { aiKeys } from "@luma/core/db/schema";

export type AiKeyRow = typeof aiKeys.$inferSelect;
export type AiKeyValues = Omit<typeof aiKeys.$inferInsert, "userId">;

export const setKeyLimit = (db: Db, userId: string, limitUsd: number) =>
  db.update(aiKeys).set({ limitUsd }).where(eq(aiKeys.userId, userId));

export const saveKey = (db: Db, userId: string, values: AiKeyValues) =>
  db
    .insert(aiKeys)
    .values({ userId, ...values })
    .onConflictDoUpdate({ target: aiKeys.userId, set: values });

export async function findKeyHash(db: Db, userId: string) {
  const [row] = await db
    .select({ keyHash: aiKeys.keyHash })
    .from(aiKeys)
    .where(eq(aiKeys.userId, userId));
  return row?.keyHash ?? null;
}
