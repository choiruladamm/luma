import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { call, ORIGIN } from "../helpers/app";
import { cookiesFrom, fakeGoogleToken } from "../helpers/google";
import { createGoogleUser } from "../helpers/session";

/** sign-in/social → Google URL + state cookie; callback with that state. */
async function loginWithGoogle(
  claims: { sub: string; email: string },
  overrides: Partial<Env> = {},
) {
  const start = await call(
    "/api/auth/sign-in/social",
    {
      method: "POST",
      headers: { "content-type": "application/json", origin: ORIGIN },
      body: JSON.stringify({ provider: "google", callbackURL: "/" }),
    },
    overrides,
  );
  expect(start.response.status).toBe(200);
  const { url } = await start.response.json<{ url: string }>();
  const google = new URL(url);
  const state = google.searchParams.get("state")!;

  fakeGoogleToken(claims);
  const callback = await call(
    `/api/auth/callback/google?code=kode&state=${encodeURIComponent(state)}`,
    { headers: { cookie: cookiesFrom(start.response).join("; ") }, redirect: "manual" },
    overrides,
  );
  return { start, google, callback };
}

const sessionCount = async (userId: string) =>
  (await env.DB.prepare("SELECT COUNT(*) AS n FROM sessions WHERE user_id = ?")
    .bind(userId)
    .first<{ n: number }>())!.n;

describe("login with Google (redirect)", () => {
  it("sign-in/social returns the Google URL for the web client without writing D1", async () => {
    const { start, google } = await loginWithGoogle({ sub: "x", email: "x@luma.test" });
    expect(google.origin).toBe("https://accounts.google.com");
    expect(google.searchParams.get("client_id")).toBe(env.GOOGLE_CLIENT_ID);
    expect(google.searchParams.get("redirect_uri")).toBe(`${ORIGIN}/api/auth/callback/google`);
    expect(start.d1Queries).toBe(0);
  });

  it("gives an admin a 7-day session cookie that passes the guard", async () => {
    const admin = await createGoogleUser("admin-google@luma.test");
    const overrides = { ADMIN_EMAILS: "admin-google@luma.test" };
    const { response, d1Queries } = (
      await loginWithGoogle({ sub: admin.sub, email: admin.email }, overrides)
    ).callback;
    // Budget (docs/budgets.md, Per-action budgets): find account + user + admin check + token update + save session.
    expect(d1Queries).toBeLessThanOrEqual(5);

    expect(response.status).toBe(302);
    expect(response.headers.get("location")).toBe("/");
    const session = response.headers
      .getSetCookie()
      .find((c) => c.startsWith("__Secure-better-auth.session_token="))!;
    expect(session).toMatch(/HttpOnly/i);
    expect(session).toMatch(/Secure/);
    expect(session).toMatch(/SameSite=Lax/i);
    expect(session).toMatch(/Max-Age=604800/);

    const probe = await call(
      "/api/__probe",
      { headers: { cookie: session.split(";")[0]! } },
      overrides,
    );
    expect(probe.response.status).toBe(404);
  });

  it("redirects an existing non-admin to /login?error without a session", async () => {
    const user = await createGoogleUser("biasa@luma.test");
    const { callback } = await loginWithGoogle({ sub: user.sub, email: user.email });

    expect(callback.response.status).toBe(302);
    expect(callback.response.headers.get("location")).toBe(
      "/login?error=FORBIDDEN&error_description=Not+an+admin",
    );
    expect(
      callback.response.headers
        .getSetCookie()
        .some((c) => c.includes("session_token=") && !c.includes("Max-Age=0")),
    ).toBe(false);
    expect(await sessionCount(user.id)).toBe(0);
  });

  it("creates the account on an admin's first sign-in (Google account linked, so the app finds it later)", async () => {
    const claims = { sub: "google-admin-baru", email: "admin-baru@luma.test" };
    const overrides = { ADMIN_EMAILS: claims.email };
    const { callback } = await loginWithGoogle(claims, overrides);

    expect(callback.response.status).toBe(302);
    expect(callback.response.headers.get("location")).toBe("/");
    const user = await env.DB.prepare("SELECT id, email_verified FROM users WHERE email = ?")
      .bind(claims.email)
      .first<{ id: string; email_verified: number }>();
    expect(user?.email_verified).toBe(1);
    const account = await env.DB.prepare(
      "SELECT provider_id, account_id FROM accounts WHERE user_id = ?",
    )
      .bind(user!.id)
      .first();
    expect(account).toEqual({ provider_id: "google", account_id: claims.sub });
    const session = callback.response.headers
      .getSetCookie()
      .find((c) => c.startsWith("__Secure-better-auth.session_token="))!;
    const probe = await call(
      "/api/__probe",
      { headers: { cookie: session.split(";")[0]! } },
      overrides,
    );
    expect(probe.response.status).toBe(404);
  });

  it("never creates an account for an email outside ADMIN_EMAILS", async () => {
    const claims = { sub: "google-baru", email: "baru@luma.test" };
    const { callback } = await loginWithGoogle(claims, { ADMIN_EMAILS: "admin@luma.test" });

    expect(callback.response.status).toBe(302);
    expect(callback.response.headers.get("location")).toBe(
      "/login?error=FORBIDDEN&error_description=Dashboard+creates+accounts+for+admins+only",
    );
    const row = await env.DB.prepare("SELECT id FROM users WHERE email = 'baru@luma.test'").first();
    expect(row).toBeNull();
  });
});
