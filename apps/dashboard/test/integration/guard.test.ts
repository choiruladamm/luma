import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { getAuth } from "../../worker/auth/auth";
import { app } from "../../worker/index";
import { call, errorCode, ORIGIN } from "../helpers/app";
import { ADMIN_EMAIL, adminCookie, createUser, sessionCookie, userCookie } from "../helpers/session";

/** A path that passes the guard then 404s: proves the guard is global, not per route. */
const PROBE = "/api/__probe";

/** Every registered admin route (middleware and /api/auth/* removed), plus the probe. */
const adminRoutes = () => [
  ...app.routes
    .filter((r) => r.method !== "ALL" && r.path.startsWith("/api/") && !r.path.startsWith("/api/auth/"))
    .map((r) => ({ method: r.method, path: r.path.replace(/:\w+/g, "x") })),
  { method: "GET", path: PROBE },
  { method: "POST", path: PROBE },
];

const jsonFromDashboard = { "content-type": "application/json", origin: ORIGIN };

describe("guard /api/*", () => {
  it("answers 401 without a cookie on every route, without touching D1", async () => {
    for (const { method, path } of adminRoutes()) {
      const { response, d1Queries } = await call(path, { method, headers: jsonFromDashboard });
      expect(response.status, `${method} ${path}`).toBe(401);
      expect(await errorCode(response)).toBe("UNAUTHORIZED");
      expect(d1Queries).toBe(0);
    }
  });

  it("answers 403 for a valid non-admin session on every route", async () => {
    const cookie = await userCookie();
    for (const { method, path } of adminRoutes()) {
      const { response } = await call(path, { method, headers: { ...jsonFromDashboard, cookie } });
      expect(response.status, `${method} ${path}`).toBe(403);
      expect(await errorCode(response)).toBe("FORBIDDEN");
    }
  });

  it("lets an admin through (probe then 404) with one D1 query", async () => {
    const { response, d1Queries } = await call(PROBE, { headers: { cookie: await adminCookie() } });
    expect(response.status).toBe(404);
    expect(await errorCode(response)).toBe("NOT_FOUND");
    expect(d1Queries).toBe(1);
  });

  it("uses the cookie name Better Auth sets", async () => {
    const { name } = (await getAuth(env).$context).authCookies.sessionToken;
    expect(name).toBe("__Secure-better-auth.session_token");
  });

  it("rejects a cookie signed with another secret (e.g. the backend's) without D1", async () => {
    const { id } = await createUser({ email: `x-${crypto.randomUUID()}@luma.test` });
    const cookie = await sessionCookie(id, { secret: "secret-backend-yang-lain-panjang-32-karakter" });
    const { response, d1Queries } = await call(PROBE, { headers: { cookie } });
    expect(response.status).toBe(401);
    expect(d1Queries).toBe(0);
  });

  it("rejects an unsigned bearer-style token (mobile session)", async () => {
    const { response } = await call(PROBE, { headers: { authorization: "Bearer abc", cookie: "__Secure-better-auth.session_token=abc" } });
    expect(response.status).toBe(401);
  });

  it("rejects an expired admin session", async () => {
    const admin = await env.DB.prepare("SELECT id FROM users WHERE email = ?").bind(ADMIN_EMAIL).first<{ id: string }>();
    const id = admin?.id ?? (await createUser({ email: ADMIN_EMAIL })).id;
    const { response } = await call(PROBE, { headers: { cookie: await sessionCookie(id, { expiresInMs: -1000 }) } });
    expect(response.status).toBe(401);
  });

  it("fails closed when ADMIN_EMAILS is empty", async () => {
    const cookie = await adminCookie();
    for (const ADMIN_EMAILS of ["", " ", ","]) {
      const { response } = await call(PROBE, { headers: { cookie } }, { ADMIN_EMAILS });
      expect(response.status, JSON.stringify(ADMIN_EMAILS)).toBe(403);
    }
  });

  it("matches emails exactly after trim + lowercase", async () => {
    const cookie = await adminCookie();
    const ok = await call(PROBE, { headers: { cookie } }, { ADMIN_EMAILS: " other@x.com , ADMIN@Luma.TEST " });
    expect(ok.response.status).toBe(404);

    const { id } = await createUser({ email: "a@x.com" });
    const near = await call(PROBE, { headers: { cookie: await sessionCookie(id) } }, { ADMIN_EMAILS: "ba@x.com,a@x.co" });
    expect(near.response.status).toBe(403);
  });

  it("requires a verified email", async () => {
    const { id } = await createUser({ email: "belum@luma.test", emailVerified: false });
    const { response } = await call(PROBE, { headers: { cookie: await sessionCookie(id) } }, { ADMIN_EMAILS: "belum@luma.test" });
    expect(response.status).toBe(403);
  });

  it("drops an existing session once the email leaves ADMIN_EMAILS", async () => {
    const cookie = await adminCookie();
    const { response } = await call(PROBE, { headers: { cookie } }, { ADMIN_EMAILS: "lain@luma.test" });
    expect(response.status).toBe(403);
  });
});

describe("mutations", () => {
  it.each([
    ["no content-type", { origin: ORIGIN }],
    ["form content-type", { "content-type": "application/x-www-form-urlencoded", origin: ORIGIN }],
    ["foreign Origin", { "content-type": "application/json", origin: "https://evil.example" }],
    ["no Origin", { "content-type": "application/json" }],
  ])("answers 403 with %s", async (_, headers) => {
    const { response } = await call(PROBE, { method: "POST", headers: { ...headers, cookie: await adminCookie() } });
    expect(response.status).toBe(403);
    expect(await errorCode(response)).toBe("FORBIDDEN");
  });

  it("passes JSON from the dashboard origin", async () => {
    const headers = { "content-type": "application/json; charset=utf-8", origin: ORIGIN, cookie: await adminCookie() };
    for (const method of ["POST", "DELETE", "PATCH"]) {
      const { response } = await call(PROBE, { method, headers });
      expect(response.status, method).toBe(404);
    }
  });
});

describe("Better Auth allowlist", () => {
  it.each([
    ["POST", "/api/auth/sign-up/email"],
    ["POST", "/api/auth/sign-in/email"],
    ["GET", "/api/auth/list-sessions"],
    ["POST", "/api/auth/update-user"],
    ["GET", "/api/auth/sign-in/social"],
    ["GET", "/api/auth/callback/github"],
    ["GET", "/api/auth/error"],
  ])("answers 404 for %s %s", async (method, path) => {
    const { response, d1Queries } = await call(path, { method, headers: jsonFromDashboard });
    expect(response.status).toBe(404);
    expect(await errorCode(response)).toBe("NOT_FOUND");
    expect(d1Queries).toBe(0);
  });

  it("serves get-session for an admin cookie", async () => {
    const { response } = await call("/api/auth/get-session", { headers: { cookie: await adminCookie() } });
    expect(response.status).toBe(200);
    expect(((await response.json()) as { user: { email: string } }).user.email).toBe(ADMIN_EMAIL);
  });
});

describe("response headers", () => {
  it.each([
    ["401", PROBE],
    ["404 auth", "/api/auth/nope"],
    ["Better Auth", "/api/auth/get-session"],
    ["non-api", "/"],
  ])("sets CSP + nosniff on %s", async (_, path) => {
    const { response } = await call(path);
    expect(response.headers.get("Content-Security-Policy")).toBe("default-src 'self'; frame-ancestors 'none'");
    expect(response.headers.get("X-Content-Type-Options")).toBe("nosniff");
  });
});

describe("rate limit", () => {
  it("answers 429 + Retry-After before auth or D1", async () => {
    const deny = { limit: async () => ({ success: false }) } as unknown as RateLimit;
    for (const path of [PROBE, "/api/auth/get-session"]) {
      const { response, d1Queries } = await call(path, {}, { RATE_LIMITER: deny });
      expect(response.status).toBe(429);
      expect(response.headers.get("Retry-After")).toBe("60");
      expect(await errorCode(response)).toBe("RATE_LIMITED");
      expect(d1Queries).toBe(0);
    }
  });

  it("keys the limiter by client IP", async () => {
    const keys: string[] = [];
    const spy = { limit: async ({ key }: { key: string }) => (keys.push(key), { success: true }) } as unknown as RateLimit;
    await call(PROBE, { headers: { "cf-connecting-ip": "10.1.2.3" } }, { RATE_LIMITER: spy });
    expect(keys).toEqual(["ip:10.1.2.3"]);
  });
});
