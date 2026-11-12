import { env } from "cloudflare:test";
import { exports } from "cloudflare:workers";
import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { createDb } from "../../src/db/client";
import { inviteCodes } from "../../src/db/schema";
import signIn from "../fixtures/contract/auth-sign-in-email.json";
import signUpFixture from "../fixtures/contract/auth-sign-up-email.json";
import invalidCredentials from "../fixtures/contract/error-invalid-credentials.json";
import invalidInvite from "../fixtures/contract/error-invalid-invite-code.json";
import { createInvite, PASSWORD, signUp } from "../helpers/auth";
import { callWithBudget } from "../helpers/budget";
import { expectContract } from "../helpers/contract";

const post = (path: string, body: unknown, headers: Record<string, string> = {}) =>
  new Request(`https://luma.test${path}`, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
  });

describe("sign-up (email, dev)", () => {
  it("creates the user with a fresh invite code and returns a bearer token (contract)", async () => {
    const code = await createInvite("BETA-0001");
    const res = await exports.default.fetch(
      post(signUpFixture.request.path, signUpFixture.request.body, { "x-invite-code": code }),
    );
    const body = (await expectContract(res, signUpFixture)) as { user: { id: string } };

    const [invite] = await createDb(env.DB).select().from(inviteCodes).where(eq(inviteCodes.code, code));
    expect(invite?.usedBy).toBe(body.user.id);
    expect(invite?.usedAt).toBeInstanceOf(Date);
  });

  it("rejects a used or unknown invite code (contract)", async () => {
    const code = await createInvite();
    await exports.default.fetch(
      post("/v1/auth/sign-up/email", { name: "A", email: "a@luma.test", password: PASSWORD }, { "x-invite-code": code }),
    );
    const reused = await exports.default.fetch(
      post("/v1/auth/sign-up/email", { name: "B", email: "b@luma.test", password: PASSWORD }, { "x-invite-code": code }),
    );
    await expectContract(reused, invalidInvite);

    const unknown = await exports.default.fetch(
      post(invalidInvite.request.path, invalidInvite.request.body, invalidInvite.request.headers),
    );
    await expectContract(unknown, invalidInvite);
  });

  it("rejects sign-up without an invite code", async () => {
    const res = await exports.default.fetch(
      post("/v1/auth/sign-up/email", { name: "C", email: "c@luma.test", password: PASSWORD }),
    );
    expect(res.status).toBe(403);
    expect(await res.json()).toMatchObject({ error: { code: "INVALID_INVITE_CODE" } });
  });

  it("accepts any sign-up once invites are switched off", async () => {
    const { response } = await callWithBudget(
      post("/v1/auth/sign-up/email", { name: "D", email: "d@luma.test", password: PASSWORD }),
      { INVITE_REQUIRED: "false" },
    );
    expect(response.status).toBe(200);
  });

  it("rejects short passwords", async () => {
    const code = await createInvite();
    const res = await exports.default.fetch(
      post("/v1/auth/sign-up/email", { name: "E", email: "e@luma.test", password: "pendek" }, { "x-invite-code": code }),
    );
    expect(res.status).toBe(400);
    expect(await res.json()).toMatchObject({ error: { code: "PASSWORD_TOO_SHORT" } });
  });
});

describe("sign-in (email, dev)", () => {
  it("returns a bearer token for the right password (contract)", async () => {
    await signUp("adam@luma.test");
    const res = await exports.default.fetch(post(signIn.request.path, signIn.request.body));
    await expectContract(res, signIn);
  });

  it("rejects a wrong password with the uniform error body (contract)", async () => {
    await signUp("adam@luma.test");
    const res = await exports.default.fetch(
      post(invalidCredentials.request.path, invalidCredentials.request.body),
    );
    await expectContract(res, invalidCredentials);
  });

  it("is disabled in prod (Google only)", async () => {
    const { response } = await callWithBudget(
      post("/v1/auth/sign-in/email", { email: "x@luma.test", password: PASSWORD }),
      { ENV: "prod" },
    );
    expect(response.status).toBeGreaterThanOrEqual(400);
    expect(await response.json()).toMatchObject({ error: { code: expect.any(String) } });
  });

  it("stays inside the budget: few D1 queries, no subrequest", async () => {
    await signUp("budget@luma.test");
    const { response, d1Queries, subrequests } = await callWithBudget(
      post("/v1/auth/sign-in/email", { email: "budget@luma.test", password: PASSWORD }),
    );
    expect(response.status).toBe(200);
    expect(d1Queries).toBeLessThanOrEqual(4);
    expect(subrequests).toBe(0);
  });

  it("rejects oversized bodies before Better Auth parses them", async () => {
    const res = await exports.default.fetch(
      post("/v1/auth/sign-in/email", { email: "x@luma.test", password: "x".repeat(20_000) }),
    );
    expect(res.status).toBe(413);
  });
});

describe("sign-out", () => {
  it("invalidates the bearer token", async () => {
    const { token } = await signUp();
    const auth = { authorization: `Bearer ${token}` };
    const out = await exports.default.fetch(post("/v1/auth/sign-out", {}, auth));
    expect(out.status).toBe(200);
    const me = await exports.default.fetch("https://luma.test/v1/me", { headers: auth });
    expect(me.status).toBe(401);
  });
});
