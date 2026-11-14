import { env } from "cloudflare:test";
import { makeSignature } from "better-auth/crypto";
import { getAuth } from "../../worker/auth/auth";
import { createDb } from "../../../backend/src/db/client";
import { accounts, aiKeys, inviteCodes, sessions, userStorage, users } from "../../../backend/src/db/schema";

export const ADMIN_EMAIL = "admin@luma.test";
let counter = 0;

export async function createUser({
  email = `user-${++counter}@luma.test`,
  emailVerified = true,
  createdAt = new Date(),
}: { email?: string; emailVerified?: boolean; createdAt?: Date } = {}) {
  const id = crypto.randomUUID();
  await createDb(env.DB).insert(users).values({ id, name: "Tester", email, emailVerified, createdAt, updatedAt: createdAt });
  return { id, email };
}

/**
 * Session cookie like a Better Auth login: the `sessions` row is written directly
 * (skipping the hook, so non-admins work too) and the token is signed with
 * HMAC-SHA256 using the dashboard BETTER_AUTH_SECRET (same format as Better
 * Auth's testUtils plugin).
 */
export async function sessionCookie(userId: string, { secret = env.BETTER_AUTH_SECRET, expiresInMs = 60_000 } = {}) {
  const token = crypto.randomUUID().replaceAll("-", "");
  const now = new Date();
  await createDb(env.DB)
    .insert(sessions)
    .values({ id: crypto.randomUUID(), token, userId, expiresAt: new Date(now.getTime() + expiresInMs), createdAt: now, updatedAt: now });
  const signed = `${token}.${await makeSignature(token, secret)}`;
  const { name } = (await getAuth(env).$context).authCookies.sessionToken;
  return `${name}=${encodeURIComponent(signed)}`;
}

/** Admin cookie (email in the test ADMIN_EMAILS). */
export async function adminCookie() {
  const existing = await env.DB.prepare("SELECT id FROM users WHERE email = ?").bind(ADMIN_EMAIL).first<{ id: string }>();
  const id = existing?.id ?? (await createUser({ email: ADMIN_EMAIL })).id;
  return sessionCookie(id);
}

/** Regular (non-admin) user cookie with a valid session. */
export async function userCookie() {
  return sessionCookie((await createUser()).id);
}

/** User with a linked Google account (like someone who signed in on the app). */
export async function createGoogleUser(email: string, sub = `google-${crypto.randomUUID()}`) {
  const user = await createUser({ email });
  const now = new Date();
  await createDb(env.DB)
    .insert(accounts)
    .values({ id: crypto.randomUUID(), accountId: sub, providerId: "google", userId: user.id, createdAt: now, updatedAt: now });
  return { ...user, sub };
}

/** Backend-owned D1 rows for a test user: AI key, usage, invite code. */
export async function giveUserData(
  userId: string,
  { keyHash, r2Bytes, syncBytes, invite }: { keyHash?: string; r2Bytes?: number; syncBytes?: number; invite?: string } = {},
) {
  const db = createDb(env.DB);
  if (keyHash) {
    await db.insert(aiKeys).values({
      userId,
      keyHash,
      keyEnc: "rahasia-terenkripsi",
      limitUsd: 0.02,
      expiresAt: new Date("2026-12-14T00:00:00Z"),
      createdAt: new Date(),
    });
  }
  if (r2Bytes !== undefined || syncBytes !== undefined) {
    await db.insert(userStorage).values({ userId, bytes: r2Bytes ?? 0, syncBytes: syncBytes ?? 0 });
  }
  if (invite) await db.insert(inviteCodes).values({ code: invite, usedBy: userId, usedAt: new Date("2026-11-01T00:00:00Z") });
}
