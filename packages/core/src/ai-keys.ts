import { eq } from "drizzle-orm";
import type { Db } from "./db/client";
import { aiKeys, users } from "./db/schema";

/** One query: banned status + stored key (null if never created). */
export async function findUserKey(db: Db, userId: string) {
  const [found] = await db
    .select({ banned: users.banned, key: aiKeys })
    .from(users)
    .leftJoin(aiKeys, eq(aiKeys.userId, users.id))
    .where(eq(users.id, userId));
  return { banned: found?.banned ?? false, key: found?.key ?? null };
}
