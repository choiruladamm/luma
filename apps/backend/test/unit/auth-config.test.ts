import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { createAuth } from "../../src/auth/auth";
import { normalizeAuthError } from "../../src/features/auth/routes";

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

describe("normalizeAuthError", () => {
  it("leaves successful and non-JSON responses untouched", async () => {
    const ok = json(200, { token: "t" });
    expect(await normalizeAuthError(ok)).toBe(ok);
    const text = new Response("nope", { status: 500 });
    expect(await normalizeAuthError(text)).toBe(text);
  });

  it("keeps a body that already has the uniform shape", async () => {
    const uniform = json(403, { error: { code: "INVALID_INVITE_CODE", message: "x" } });
    expect(await normalizeAuthError(uniform)).toBe(uniform);
  });

  it("wraps Better Auth {code, message} and keeps the status", async () => {
    const res = await normalizeAuthError(json(422, { code: "USER_ALREADY_EXISTS", message: "dup" }));
    expect(res.status).toBe(422);
    expect(await res.json()).toEqual({ error: { code: "USER_ALREADY_EXISTS", message: "dup" } });
  });

  it.each([
    [401, "UNAUTHORIZED"],
    [404, "NOT_FOUND"],
    [413, "PAYLOAD_TOO_LARGE"],
    [429, "RATE_LIMITED"],
    [500, "INTERNAL_ERROR"],
    [400, "BAD_REQUEST"],
  ])("derives a code from status %i when Better Auth sends none", async (status, code) => {
    const res = await normalizeAuthError(json(status, { message: "m" }));
    expect(await res.json()).toEqual({ error: { code, message: "m" } });
  });
});

describe("createAuth", () => {
  it("turns Google off when no client IDs are configured", () => {
    const auth = createAuth({ ...env, GOOGLE_CLIENT_IDS: "" });
    expect(auth.options.socialProviders).toEqual({});
  });

  it("accepts idTokens from every listed Google client ID", () => {
    const auth = createAuth({ ...env, GOOGLE_CLIENT_IDS: "web.apps, ios.apps ,android.apps" });
    expect(auth.options.socialProviders?.google?.clientId).toEqual([
      "web.apps",
      "ios.apps",
      "android.apps",
    ]);
  });

  it("enables email + password everywhere except prod", () => {
    expect(createAuth({ ...env, ENV: "dev" }).options.emailAndPassword?.enabled).toBe(true);
    expect(createAuth({ ...env, ENV: "prod" }).options.emailAndPassword?.enabled).toBe(false);
  });
});
