// Semua query D1 dashboard. Tiap fungsi = satu unit anggaran query.
import { eq } from "drizzle-orm";
import type { Db } from "../../backend/src/db/client";
import { sessions, users } from "../../backend/src/db/schema";

/** 1 query: data yang dibutuhkan cek admin di hook `session.create.before`. */
export async function findUserForAdminCheck(db: Db, userId: string) {
  const [row] = await db
    .select({ email: users.email, emailVerified: users.emailVerified })
    .from(users)
    .where(eq(users.id, userId))
    .limit(1);
  return row ?? null;
}

/** 1 query: sesi dari cookie + user pemiliknya. Kolom dipilih eksplisit. */
export async function findSession(db: Db, token: string) {
  const [row] = await db
    .select({
      expiresAt: sessions.expiresAt,
      id: users.id,
      email: users.email,
      emailVerified: users.emailVerified,
    })
    .from(sessions)
    .innerJoin(users, eq(users.id, sessions.userId))
    .where(eq(sessions.token, token))
    .limit(1);
  return row ?? null;
}
