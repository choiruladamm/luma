import { env } from "cloudflare:test";
import { makeSignature } from "better-auth/crypto";
import { getAuth } from "../../worker/auth";
import { createDb } from "../../../backend/src/db/client";
import { accounts, sessions, users } from "../../../backend/src/db/schema";

export const ADMIN_EMAIL = "admin@luma.test";
let counter = 0;

export async function createUser({ email = `user-${++counter}@luma.test`, emailVerified = true } = {}) {
  const id = crypto.randomUUID();
  await createDb(env.DB).insert(users).values({ id, name: "Tester", email, emailVerified });
  return { id, email };
}

/**
 * Cookie sesi seperti hasil login Better Auth: baris `sessions` ditulis langsung
 * (melewati hook, jadi bisa buat non-admin) lalu tokennya ditandatangani
 * HMAC-SHA256 dengan BETTER_AUTH_SECRET dashboard (format yang sama dengan
 * plugin testUtils Better Auth).
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

/** Cookie admin (email di ADMIN_EMAILS test). */
export async function adminCookie() {
  const existing = await env.DB.prepare("SELECT id FROM users WHERE email = ?").bind(ADMIN_EMAIL).first<{ id: string }>();
  const id = existing?.id ?? (await createUser({ email: ADMIN_EMAIL })).id;
  return sessionCookie(id);
}

/** Cookie user biasa (bukan admin), sesi valid. */
export async function userCookie() {
  return sessionCookie((await createUser()).id);
}

/** User dengan akun Google tertaut (seperti user yang sudah login di app). */
export async function createGoogleUser(email: string, sub = `google-${crypto.randomUUID()}`) {
  const user = await createUser({ email });
  const now = new Date();
  await createDb(env.DB)
    .insert(accounts)
    .values({ id: crypto.randomUUID(), accountId: sub, providerId: "google", userId: user.id, createdAt: now, updatedAt: now });
  return { ...user, sub };
}
