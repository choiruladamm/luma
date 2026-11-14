// Session and user queries for admin auth (used by `requireAdmin` and the Better Auth hook).
import { eq } from "drizzle-orm";
import type { Db } from "../../../backend/src/db/client";
import { sessions, users } from "../../../backend/src/db/schema";

/** Better Auth session cookie name: `__Secure-` prefix when the base URL is https. */
export const sessionCookieName = (env: Env) =>
  env.BETTER_AUTH_URL.startsWith("https://") ? "__Secure-better-auth.session_token" : "better-auth.session_token";

/** 1 query: what the admin check in the `session.create.before` hook needs. */
export async function findUserForAdminCheck(db: Db, userId: string) {
  const [row] = await db
    .select({ email: users.email, emailVerified: users.emailVerified })
    .from(users)
    .where(eq(users.id, userId))
    .limit(1);
  return row ?? null;
}

/** 1 query: the cookie's session + its user. Columns picked explicitly. */
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
