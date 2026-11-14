import { env } from "cloudflare:test";
import { exports } from "cloudflare:workers";
import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { createDb } from "../../src/db/client";
import { inviteCodes } from "../../src/db/schema";
import signInSocial from "../fixtures/contract/auth-sign-in-social.json";
import inviteRequired from "../fixtures/contract/error-invite-code-required.json";
import { createInvite } from "../helpers/auth";
import { callWithBudget } from "../helpers/budget";
import { expectContract } from "../helpers/contract";
import { fakeGoogle, foreignToken } from "../helpers/google";

const signIn = (token: string, invite?: string) =>
  new Request(`https://luma.test${signInSocial.request.path}`, {
    method: "POST",
    headers: { "content-type": "application/json", ...(invite ? { "x-invite-code": invite } : {}) },
    body: JSON.stringify({ provider: "google", idToken: { token } }),
  });

const errorCode = async (res: Response) => ((await res.json()) as { error: { code: string } }).error.code;

describe("sign-in with Google idToken", () => {
  it("creates the account with an invite code and returns a bearer token (contract, budget)", async () => {
    const google = await fakeGoogle();
    const code = await createInvite("LUMA-7Q2K");
    const token = await google.idToken({ sub: "google-adam" });

    const { response, d1Queries, subrequests } = await callWithBudget(signIn(token, code));
    const body = (await expectContract(response, signInSocial)) as { user: { id: string } };

    // Satu fetch JWKS Google, sisanya D1 (docs/backend.md, Anggaran per aksi).
    expect(subrequests).toBe(1);
    expect(google.certFetches()).toBe(1);
    expect(d1Queries).toBeLessThanOrEqual(8);
    const [invite] = await createDb(env.DB).select().from(inviteCodes).where(eq(inviteCodes.code, code));
    expect(invite?.usedBy).toBe(body.user.id);
  });

  it("asks a new Google account for an invite code (contract)", async () => {
    const google = await fakeGoogle();
    const res = await exports.default.fetch(signIn(await google.idToken({ email: "baru@gmail.test" })));

    expect(res.status).toBe(inviteRequired.response.status);
    expect(await errorCode(res)).toBe("INVITE_CODE_REQUIRED");
  });

  it("lets a returning Google account in without a code, same user", async () => {
    const google = await fakeGoogle();
    const claims = { sub: "google-balik", email: "balik@gmail.test" };
    const first = await exports.default.fetch(signIn(await google.idToken(claims), await createInvite()));
    const again = await exports.default.fetch(signIn(await google.idToken(claims)));

    expect(first.status).toBe(200);
    expect(again.status).toBe(200);
    expect(again.headers.get("set-auth-token")).toBeTruthy();
    const ids = await Promise.all([first, again].map(async (r) => ((await r.json()) as { user: { id: string } }).user.id));
    expect(ids[1]).toBe(ids[0]);
  });

  it("accepts the iOS and Android client IDs as audience", async () => {
    const google = await fakeGoogle();
    const clients = env.GOOGLE_CLIENT_IDS.split(",").map((s) => s.trim());
    expect(clients.length).toBeGreaterThanOrEqual(3);

    for (const [i, aud] of clients.slice(1).entries()) {
      const token = await google.idToken({ sub: `google-aud-${i}`, email: `aud-${i}@gmail.test` }, { aud });
      const res = await exports.default.fetch(signIn(token, await createInvite()));
      expect(res.status, aud).toBe(200);
    }
  });

  it.each([
    ["another app's audience", { aud: "123-orang-lain.apps.googleusercontent.com" }],
    ["a non-Google issuer", { iss: "https://evil.example" }],
    ["an expired token", { expiresIn: "-1m" }],
  ])("rejects %s", async (_, opts) => {
    const google = await fakeGoogle();
    const token = await google.idToken({ sub: "google-tolak" }, opts);
    const res = await exports.default.fetch(signIn(token, await createInvite()));

    expect(res.status).toBe(401);
    expect(await errorCode(res)).toBe("INVALID_TOKEN");
  });

  it("rejects a token signed by a key Google never published", async () => {
    await fakeGoogle();
    const res = await exports.default.fetch(signIn(await foreignToken(), await createInvite()));

    expect(res.status).toBe(401);
    expect(await errorCode(res)).toBe("INVALID_TOKEN");
  });
});
