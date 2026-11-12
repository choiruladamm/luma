import { env } from "cloudflare:test";
import { exports } from "cloudflare:workers";
import { createDb } from "../../src/db/client";
import { inviteCodes } from "../../src/db/schema";

export const PASSWORD = "rahasia-banget-123";
let counter = 0;

/** Bikin kode undangan baru di D1 dan kembalikan kodenya. */
export async function createInvite(code = `TEST-${++counter}-${crypto.randomUUID().slice(0, 8)}`) {
  await createDb(env.DB).insert(inviteCodes).values({ code: code.toUpperCase() });
  return code.toUpperCase();
}

export type SignedUp = { token: string; userId: string; email: string };

/**
 * Daftar lewat endpoint asli (email + kode undangan), kembalikan bearer token.
 * Storage D1 dipakai bareng dalam satu file test: email yang udah ada → login.
 */
export async function signUp(email = `user-${++counter}@luma.test`): Promise<SignedUp> {
  const invite = await createInvite();
  let res = await exports.default.fetch("https://luma.test/v1/auth/sign-up/email", {
    method: "POST",
    headers: { "content-type": "application/json", "x-invite-code": invite },
    body: JSON.stringify({ name: "Tester", email, password: PASSWORD }),
  });
  if (res.status === 422) {
    res = await exports.default.fetch("https://luma.test/v1/auth/sign-in/email", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email, password: PASSWORD }),
    });
  }
  if (!res.ok) throw new Error(`signUp failed: ${res.status} ${await res.text()}`);
  const body = (await res.json()) as { token: string; user: { id: string } };
  return { token: res.headers.get("set-auth-token") ?? body.token, userId: body.user.id, email };
}

/** Header Authorization untuk user baru. */
export async function bearer(): Promise<Record<string, string> & { userId: string }> {
  const user = await signUp();
  return Object.assign({ authorization: `Bearer ${user.token}` }, { userId: user.userId });
}
