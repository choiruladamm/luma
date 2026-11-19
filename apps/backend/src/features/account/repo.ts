import { eq } from "drizzle-orm";
import type { Db } from "@luma/core/db/client";
import { users } from "@luma/core/db/schema";

/** Deletes the user row; sessions, login accounts, AI key, storage, and records cascade. */
export const deleteUser = (db: Db, userId: string) => db.delete(users).where(eq(users.id, userId));
