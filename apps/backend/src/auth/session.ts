import { eq } from "drizzle-orm";
import type { Db } from "@luma/core/db/client";
import { sessions, users } from "@luma/core/db/schema";
import type { SessionUser } from "@luma/contracts/backend/account";
import { DAY_MS } from "@luma/core/encoding";

/** Matches Better Auth's `session` options (auth.ts): 60-day sessions, renewed at most once a day. */
export const SESSION_EXPIRES_IN_MS = 60 * DAY_MS;
export const SESSION_UPDATE_AGE_MS = DAY_MS;

/**
 * Token from `Authorization: Bearer <token>`. The `set-auth-token` header has the form
 * `<token>.<signature>`; only the token part (random, secret) is matched against D1.
 */
export function bearerToken(header: string | undefined): string | null {
  const match = header?.match(/^Bearer\s+(\S+)$/i);
  const token = match?.[1]?.split(".")[0];
  return token ? token : null;
}

/**
 * Checks the session for Luma routes (not /v1/auth): one join query, without building
 * the heavy Better Auth instance. Session renewal writes D1 at most once a day.
 */
export async function findSessionUser(db: Db, header: string | undefined, now = new Date()) {
  const token = bearerToken(header);
  if (!token) return null;
  const [row] = await db
    .select({
      sessionId: sessions.id,
      expiresAt: sessions.expiresAt,
      id: users.id,
      name: users.name,
      email: users.email,
      image: users.image,
    })
    .from(sessions)
    .innerJoin(users, eq(users.id, sessions.userId))
    .where(eq(sessions.token, token))
    .limit(1);
  if (!row || row.expiresAt.getTime() <= now.getTime()) return null;

  if (row.expiresAt.getTime() - now.getTime() < SESSION_EXPIRES_IN_MS - SESSION_UPDATE_AGE_MS) {
    await db
      .update(sessions)
      .set({ expiresAt: new Date(now.getTime() + SESSION_EXPIRES_IN_MS), updatedAt: now })
      .where(eq(sessions.id, row.sessionId));
  }
  const user: SessionUser = {
    id: row.id,
    name: row.name,
    email: row.email,
    image: row.image ?? null,
  };
  return user;
}
