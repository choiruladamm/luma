import { eq } from "drizzle-orm";
import type { Db } from "../../db/client";
import { users } from "../../db/schema";

/** Hapus baris user; sesi, akun login, key AI, storage, records ikut cascade. */
export const deleteUser = (db: Db, userId: string) => db.delete(users).where(eq(users.id, userId));
