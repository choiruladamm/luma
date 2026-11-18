import { env } from "cloudflare:test";
import { exports } from "cloudflare:workers";
import { createDb } from "../../src/db/client";
import { normalizeInviteCode } from "../../src/auth/invite";
import { inviteCodes } from "../../src/db/schema";

export const PASSWORD = "rahasia-banget-123";
let counter = 0;

/** Creates a new invite code in D1 and returns it. */
export async function createInvite(code = `TEST-${++counter}-${crypto.randomUUID().slice(0, 8)}`) {
  const normalized = normalizeInviteCode(code);
  await createDb(env.DB).insert(inviteCodes).values({ code: normalized });
  return normalized;
}

export type SignedUp = { token: string; userId: string; email: string };

/**
 * Signs up through the real endpoint (email + invite code) and returns the bearer token.
 * D1 storage is shared within a test file: an email that already exists → sign in instead.
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
  const body = await res.json<{ token: string; user: { id: string } }>();
  return { token: res.headers.get("set-auth-token") ?? body.token, userId: body.user.id, email };
}

/** Authorization header for a new user. */
export async function bearer(): Promise<Record<string, string> & { userId: string }> {
  const user = await signUp();
  return Object.assign({ authorization: `Bearer ${user.token}` }, { userId: user.userId });
}
