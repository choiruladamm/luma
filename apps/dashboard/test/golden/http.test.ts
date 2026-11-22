import {
  sessionResponse,
  signOutResponse,
  socialSignInResponse,
} from "@luma/contracts/dashboard/auth";
import { inviteCreateResponse, inviteListResponse } from "@luma/contracts/dashboard/invites";
import { overviewResponse, overviewUsageResponse } from "@luma/contracts/dashboard/overview";
import {
  banResponse,
  unbanResponse,
  userDetailResponse,
  userListResponse,
  userUsageResponse,
} from "@luma/contracts/dashboard/users";
import type { ZodType } from "zod";
import { HttpResponse, http } from "msw";
import { expect, it, vi } from "vitest";
import { OPENROUTER_API } from "@luma/core/openrouter";
import { call, ORIGIN } from "../helpers/app";
import { GOLDEN_NOW, goldenJson, record, type Recorded } from "../helpers/golden";
import { cookiesFrom, fakeGoogleToken } from "../helpers/google";
import { fakeOpenRouter } from "../helpers/openrouter";
import {
  adminCookie,
  createGoogleUser,
  createUser,
  giveUserData,
  userCookie,
} from "../helpers/session";
import { network } from "../setup";

/** Success response contract per step; every error response is checked against the shared error body. */
const contracts: Record<string, ZodType> = {
  "GET /api/auth/get-session signed out": sessionResponse,
  "GET /api/auth/get-session": sessionResponse,
  "POST /api/auth/sign-in/social": socialSignInResponse,
  "POST /api/auth/sign-out": signOutResponse,
  "GET /api/users": userListResponse,
  "GET /api/users filtered": userListResponse,
  "GET /api/users/:id": userDetailResponse,
  "GET /api/users/:id no key": userDetailResponse,
  "GET /api/users/:id after 502": userDetailResponse,
  "GET /api/users/:id/usage": userUsageResponse,
  "POST /api/users/:id/ban": banResponse,
  "POST /api/users/:id/unban": unbanResponse,
  "GET /api/invites": inviteListResponse,
  "GET /api/invites filtered": inviteListResponse,
  "POST /api/invites": inviteCreateResponse,
  "GET /api/overview": overviewResponse,
  "GET /api/overview/usage": overviewUsageResponse,
};

const deny = { limit: async () => ({ success: false }) } as unknown as RateLimit;

/**
 * Every dashboard Worker route with its success and error cases, recorded in full (status,
 * headers, body, D1 queries, subrequests). The refactor phases of the worker platform must keep
 * this file byte-identical; an intended change shows up as a reviewable diff.
 */
it("records every route", async () => {
  vi.useFakeTimers({ toFake: ["Date"], now: GOLDEN_NOW });
  const steps: Record<string, Recorded> = {};
  // Rows created in the same millisecond have no defined order; one second apart, lists are stable.
  const tick = () => vi.setSystemTime(Date.now() + 1000);
  const step = async (name: string, path: string, init: RequestInit = {}, overrides = {}) => {
    steps[name] = await record(path, init, overrides, contracts[name]).catch((e: Error) => {
      throw new Error(`${name}: ${e.message}`, { cause: e });
    });
    tick();
  };
  network.use(
    http.get(`${OPENROUTER_API}/activity`, () =>
      HttpResponse.json({ data: [{ date: "2026-11-13", usage: 0.42 }] }),
    ),
  );

  const admin = { cookie: await adminCookie() };
  tick();
  const mutate = (body?: unknown, method = "POST"): RequestInit => ({
    method,
    headers: { ...admin, "content-type": "application/json", origin: ORIGIN },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const member = await createUser({ email: "member@luma.test", name: "Member" });
  tick();
  await giveUserData(member.id, { keyHash: "hash-member", r2Bytes: 2048, syncBytes: 512 });
  const plain = await createUser({ email: "plain@luma.test", name: "Plain" });
  tick();
  fakeOpenRouter({ keys: ["hash-member"] });

  // Guards and routing.
  await step("GET /api/users 401", "/api/users");
  await step("GET /api/users 403 non-admin", "/api/users", {
    headers: { cookie: await userCookie() },
  });
  await step("GET /api/unknown 401", "/api/unknown");
  await step("GET /api/unknown 404", "/api/unknown", { headers: admin });
  await step("GET /api/users 429 ip", "/api/users", { headers: admin }, { RATE_LIMITER: deny });

  // Better Auth.
  await step("GET /api/auth/get-session signed out", "/api/auth/get-session");
  await step("GET /api/auth/get-session", "/api/auth/get-session", { headers: admin });
  await step("POST /api/auth/sign-in/social", "/api/auth/sign-in/social", {
    method: "POST",
    headers: { "content-type": "application/json", origin: ORIGIN },
    body: JSON.stringify({ provider: "google", callbackURL: "/" }),
  });
  const googleAdmin = await createGoogleUser("admin-google@luma.test", "google-admin");
  tick();
  const callback = async (name: string, state?: string) => {
    const start = await call("/api/auth/sign-in/social", {
      method: "POST",
      headers: { "content-type": "application/json", origin: ORIGIN },
      body: JSON.stringify({ provider: "google", callbackURL: "/" }),
    });
    const { url } = await start.response.json<{ url: string }>();
    fakeGoogleToken({ sub: googleAdmin.sub, email: googleAdmin.email });
    const realState = new URL(url).searchParams.get("state")!;
    await step(
      name,
      `/api/auth/callback/google?code=kode&state=${encodeURIComponent(state ?? realState)}`,
      { headers: { cookie: cookiesFrom(start.response).join("; ") } },
      { ADMIN_EMAILS: googleAdmin.email },
    );
  };
  await callback("GET /api/auth/callback/google");
  await callback("GET /api/auth/callback/google bad state", "wrong-state");
  await step("POST /api/auth/sign-up/email hidden 404", "/api/auth/sign-up/email", {
    method: "POST",
    headers: { "content-type": "application/json", origin: ORIGIN },
    body: "{}",
  });

  // Users.
  await step("GET /api/users", "/api/users", { headers: admin });
  await step("GET /api/users filtered", "/api/users?q=member&ai=yes&sort=r2&dir=asc", {
    headers: admin,
  });
  await step("GET /api/users 400", "/api/users?sort=nope", { headers: admin });
  await step("GET /api/users/:id", `/api/users/${member.id}`, { headers: admin });
  await step("GET /api/users/:id no key", `/api/users/${plain.id}`, { headers: admin });
  await step("GET /api/users/:id 404", "/api/users/missing-user", { headers: admin });
  await step("GET /api/users/:id 400", "/api/users/bad%20id", { headers: admin });
  await step("GET /api/users/:id/usage", `/api/users/${member.id}/usage`, { headers: admin });
  await step("GET /api/users/:id/usage 400", `/api/users/${member.id}/usage?days=0`, {
    headers: admin,
  });
  await step("GET /api/users/:id/usage 404", "/api/users/missing-user/usage", { headers: admin });
  await step("POST /api/users/:id/ban 403 origin", `/api/users/${member.id}/ban`, {
    method: "POST",
    headers: { ...admin, "content-type": "application/json" },
  });
  await step("POST /api/users/:id/ban 403 not json", `/api/users/${member.id}/ban`, {
    method: "POST",
    headers: { ...admin, origin: ORIGIN },
  });
  await step("POST /api/users/:id/ban 429 admin", `/api/users/${member.id}/ban`, mutate(), {
    ADMIN_RATE_LIMITER: deny,
  });
  await step("POST /api/users/:id/ban", `/api/users/${member.id}/ban`, mutate());
  await step("POST /api/users/:id/ban 404", "/api/users/missing-user/ban", mutate());
  const failing = await createUser({ email: "failing@luma.test", name: "Failing" });
  tick();
  await giveUserData(failing.id, { keyHash: "hash-failing" });
  fakeOpenRouter({ keys: ["hash-failing"], fail: true });
  await step("POST /api/users/:id/ban 502", `/api/users/${failing.id}/ban`, mutate());
  await step("GET /api/users/:id after 502", `/api/users/${failing.id}`, { headers: admin });
  await step("POST /api/users/:id/unban", `/api/users/${member.id}/unban`, mutate());
  await step("POST /api/users/:id/unban 404", "/api/users/missing-user/unban", mutate());

  // Invites.
  await giveUserData(plain.id, { invite: "LUMA-USED222222" });
  await step("POST /api/invites", "/api/invites", mutate({ count: 2 }));
  await step("POST /api/invites 400", "/api/invites", mutate({ count: 0 }));
  await step("POST /api/invites 400 malformed", "/api/invites", {
    ...mutate(),
    body: "{not json",
  });
  await step("POST /api/invites 413", "/api/invites", mutate({ pad: "x".repeat(17 * 1024) }));
  await step("GET /api/invites", "/api/invites", { headers: admin });
  await step("GET /api/invites filtered", "/api/invites?status=used&sort=code&dir=asc", {
    headers: admin,
  });
  await step("GET /api/invites 400", "/api/invites?limit=500", { headers: admin });
  const unused = (await fetchInvites(admin))[0];
  await step("DELETE /api/invites/:code", `/api/invites/${unused}`, mutate(undefined, "DELETE"));
  await step(
    "DELETE /api/invites/:code 404",
    `/api/invites/${unused}`,
    mutate(undefined, "DELETE"),
  );
  await step(
    "DELETE /api/invites/:code 409 used",
    "/api/invites/LUMA-USED222222",
    mutate(undefined, "DELETE"),
  );
  await step("DELETE /api/invites/:code 400", "/api/invites/x", mutate(undefined, "DELETE"));

  // Overview.
  await step("GET /api/overview", "/api/overview", { headers: admin });
  await step("GET /api/overview/usage", "/api/overview/usage", { headers: admin });
  await step("GET /api/overview/usage 400", "/api/overview/usage?days=0", { headers: admin });

  // Sign-out last: it ends the admin session used above.
  await step("POST /api/auth/sign-out", "/api/auth/sign-out", mutate({}));

  // Non-API paths are served by static assets, not the Worker.
  await step("GET /other 404", "/other");

  vi.useRealTimers();
  await expect(goldenJson(steps)).toMatchFileSnapshot("./http.golden.json");
});

/** Real invite codes (the recorded list masks them). */
async function fetchInvites(admin: { cookie: string }) {
  const { response } = await call("/api/invites?status=unused", { headers: admin });
  return (await response.json<{ items: { code: string }[] }>()).items.map((i) => i.code);
}
