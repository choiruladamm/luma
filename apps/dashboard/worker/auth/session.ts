// Session and user queries for admin auth (used by `requireAdmin` and the Better Auth hook).
import { and, eq, lt } from "drizzle-orm";
import type { Db } from "../../../backend/src/db/client";
import { sessions, users } from "../../../backend/src/db/schema";

/** Better Auth session cookie name: `__Secure-` prefix when the base URL is https. */
export const sessionCookieName = (env: Env) =>
  env.BETTER_AUTH_URL.startsWith("https://") ? "__Secure-better-auth.session_token" : "better-auth.session_token";

/** Absolute limit from sign-in, however much the session is used: Google sign-in again after 30 days. */
export const SESSION_MAX_AGE_MS = 30 * 24 * 60 * 60 * 1000;

export const isPastMaxAge = (createdAt: Date, now = Date.now()) => now - createdAt.getTime() >= SESSION_MAX_AGE_MS;

/** 1 query: delete the cookie's session if it's past the absolute limit (no-op otherwise). */
export const endSessionIfPastMaxAge = (db: Db, token: string, now = Date.now()) =>
  db.delete(sessions).where(and(eq(sessions.token, token), lt(sessions.createdAt, new Date(now - SESSION_MAX_AGE_MS))));

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
      createdAt: sessions.createdAt,
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
