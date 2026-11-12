import { eq } from "drizzle-orm";
import type { Db } from "../db/client";
import { sessions, users } from "../db/schema";
import type { SessionUser } from "../env";

const DAY_MS = 24 * 60 * 60 * 1000;

/** Sama dengan opsi `session` Better Auth (auth.ts): sesi 60 hari, diperpanjang maks sekali sehari. */
export const SESSION_EXPIRES_IN_MS = 60 * DAY_MS;
export const SESSION_UPDATE_AGE_MS = DAY_MS;

/**
 * Token dari `Authorization: Bearer <token>`. Header `set-auth-token` berbentuk
 * `<token>.<signature>`; yang dicocokkan ke D1 cuma bagian token (acak, rahasia).
 */
export function bearerToken(header: string | undefined): string | null {
  const match = header?.match(/^Bearer\s+(\S+)$/i);
  const token = match?.[1]?.split(".")[0];
  return token ? token : null;
}

/**
 * Cek sesi untuk route Luma (bukan /v1/auth): satu query join, tanpa membangun
 * instance Better Auth yang berat. Perpanjangan sesi menulis D1 paling sering sekali sehari.
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
  const user: SessionUser = { id: row.id, name: row.name, email: row.email, image: row.image ?? null };
  return user;
}
