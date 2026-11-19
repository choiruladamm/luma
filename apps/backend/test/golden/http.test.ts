import { env } from "cloudflare:test";
import { eq } from "drizzle-orm";
import { expect, it, vi } from "vitest";
import { createDb } from "../../src/db/client";
import { users } from "../../src/db/schema";
import aiKeyRotate from "../fixtures/contract/ai-key-rotate.json";
import backupsPut from "../fixtures/contract/backups-put.json";
import signInEmail from "../fixtures/contract/auth-sign-in-email.json";
import signInSocial from "../fixtures/contract/auth-sign-in-social.json";
import signUpEmail from "../fixtures/contract/auth-sign-up-email.json";
import syncPushOlder from "../fixtures/contract/sync-push-older-schema.json";
import syncPushTombstone from "../fixtures/contract/sync-push-tombstone.json";
import syncPush from "../fixtures/contract/sync-push.json";
import { createInvite, signUp } from "../helpers/auth";
import { callWithBudget } from "../helpers/budget";
import { GOLDEN_NOW, goldenJson, record, type Recorded } from "../helpers/golden";
import { fakeGoogle, foreignToken } from "../helpers/google";
import { fakeOpenRouter } from "../helpers/openrouter";

const deny = { limit: async () => ({ success: false }) } as unknown as RateLimit;
/** Denies only the per-user limit, so the request passes the IP limit and reaches the session. */
const denyUser = {
  limit: async ({ key }: { key: string }) => ({ success: !key.startsWith("user:") }),
};
const off = (flag: "SYNC_ENABLED" | "BACKUP_ENABLED" | "AI_KEY_ENABLED") => ({ [flag]: "false" });

type Init = { method?: string; token?: string; headers?: Record<string, string>; body?: unknown };

/** Builds a request; an object body is sent as JSON, a string body as is with its length. */
function req(path: string, { method = "GET", token, headers = {}, body }: Init = {}) {
  const h: Record<string, string> = { ...headers };
  if (token) h.authorization = `Bearer ${token}`;
  let payload: string | undefined;
  if (typeof body === "string") {
    payload = body;
    h["content-length"] ??= String(body.length);
  } else if (body !== undefined) {
    payload = JSON.stringify(body);
    h["content-type"] = "application/json";
  }
  return new Request(`https://luma.test${path}`, { method, headers: h, body: payload });
}

/**
 * Every backend route with its success and error cases, recorded in full (status, headers, body,
 * D1 queries, subrequests). The refactor phases of the worker platform must keep this file
 * byte-identical; an intended change shows up as a reviewable diff.
 */
it("records every route", async () => {
  vi.useFakeTimers({ toFake: ["Date"], now: GOLDEN_NOW });
  const steps: Record<string, Recorded> = {};
  const step = async (name: string, request: Request, overrides: Partial<Env> = {}) => {
    steps[name] = await record(request, overrides);
  };
  fakeOpenRouter();
  const google = await fakeGoogle();

  // Health, routing.
  await step("GET /v1/health", req("/v1/health"));
  await step("GET /v1/health 429", req("/v1/health"), { RATE_LIMITER: deny });
  await step("GET /v1/unknown 404", req("/v1/unknown"));
  await step("GET /unknown 404", req("/unknown"));

  // Auth.
  await createInvite("BETA-0001");
  await step(
    "POST /v1/auth/sign-up/email",
    req("/v1/auth/sign-up/email", {
      method: "POST",
      headers: signUpEmail.request.headers,
      body: signUpEmail.request.body,
    }),
  );
  await step(
    "POST /v1/auth/sign-up/email used invite",
    req("/v1/auth/sign-up/email", {
      method: "POST",
      headers: { "x-invite-code": "BETA-0001" },
      body: { name: "Other", email: "other@luma.test", password: "rahasia-banget-123" },
    }),
  );
  await step(
    "POST /v1/auth/sign-up/email invalid invite",
    req("/v1/auth/sign-up/email", {
      method: "POST",
      headers: { "x-invite-code": "NOPE-0000" },
      body: { name: "Other", email: "other@luma.test", password: "rahasia-banget-123" },
    }),
  );
  await step(
    "POST /v1/auth/sign-up/email no invite",
    req("/v1/auth/sign-up/email", {
      method: "POST",
      body: { name: "Other", email: "other@luma.test", password: "rahasia-banget-123" },
    }),
  );
  await step(
    "POST /v1/auth/sign-up/email 413",
    req("/v1/auth/sign-up/email", { method: "POST", body: { name: "x".repeat(17 * 1024) } }),
  );
  await step(
    "POST /v1/auth/sign-in/email",
    req("/v1/auth/sign-in/email", { method: "POST", body: signInEmail.request.body }),
  );
  await step(
    "POST /v1/auth/sign-in/email wrong password",
    req("/v1/auth/sign-in/email", {
      method: "POST",
      body: { ...signInEmail.request.body, password: "salah-banget-123" },
    }),
  );
  await step(
    "POST /v1/auth/sign-in/email invalid body",
    req("/v1/auth/sign-in/email", { method: "POST", body: { email: "not-an-email" } }),
  );
  await createInvite("LUMA-7Q2K");
  await step(
    "POST /v1/auth/sign-in/social",
    req("/v1/auth/sign-in/social", {
      method: "POST",
      headers: signInSocial.request.headers,
      body: {
        provider: "google",
        idToken: { token: await google.idToken({ email: "golden@gmail.test", sub: "google-1" }) },
      },
    }),
  );
  await step(
    "POST /v1/auth/sign-in/social foreign token",
    req("/v1/auth/sign-in/social", {
      method: "POST",
      body: { provider: "google", idToken: { token: await foreignToken() } },
    }),
  );
  await step(
    "POST /v1/auth/update-user hidden 404",
    req("/v1/auth/update-user", { method: "POST", body: {} }),
  );
  await step("GET /v1/auth/sign-in/email 404", req("/v1/auth/sign-in/email"));
  const leaving = await signUp("leaving@luma.test");
  await step(
    "POST /v1/auth/sign-out",
    req("/v1/auth/sign-out", { method: "POST", token: leaving.token, body: {} }),
  );

  const { token, userId } = await signUp("golden@luma.test");

  // Account.
  await step("GET /v1/me", req("/v1/me", { token }));
  await step("GET /v1/me 401", req("/v1/me"));
  await step("GET /v1/me 401 bad token", req("/v1/me", { token: "not-a-token" }));
  await step("DELETE /v1/me 401", req("/v1/me", { method: "DELETE" }));

  // AI key.
  await step("POST /v1/ai/key", req("/v1/ai/key", { method: "POST", token, body: {} }));
  await step(
    "POST /v1/ai/key rotate",
    req("/v1/ai/key", { method: "POST", token, body: aiKeyRotate.request.body }),
  );
  await step(
    "POST /v1/ai/key 400",
    req("/v1/ai/key", { method: "POST", token, body: { rotate: "yes" } }),
  );
  await step(
    "POST /v1/ai/key 413",
    req("/v1/ai/key", { method: "POST", token, body: { pad: "x".repeat(2048) } }),
  );
  await step("POST /v1/ai/key 401", req("/v1/ai/key", { method: "POST", body: {} }));
  await step(
    "POST /v1/ai/key 503",
    req("/v1/ai/key", { method: "POST", token, body: {} }),
    off("AI_KEY_ENABLED"),
  );
  await step("POST /v1/ai/key user limit", req("/v1/ai/key", { method: "POST", token, body: {} }), {
    RATE_LIMITER: denyUser,
  });
  await step("GET /v1/ai/usage", req("/v1/ai/usage", { token }));
  await step("GET /v1/ai/usage 401", req("/v1/ai/usage"));
  await step("GET /v1/ai/usage 503", req("/v1/ai/usage", { token }), off("AI_KEY_ENABLED"));
  await step("GET /v1/ai/usage no user limit", req("/v1/ai/usage", { token }), {
    RATE_LIMITER: denyUser,
  });
  await step("GET /v1/ai/config", req("/v1/ai/config", { token }));
  await step("GET /v1/ai/config 401", req("/v1/ai/config"));
  await step("GET /v1/ai/config 503", req("/v1/ai/config", { token }), off("AI_KEY_ENABLED"));
  await step("GET /v1/ai/config no user limit", req("/v1/ai/config", { token }), {
    RATE_LIMITER: denyUser,
  });

  // Files.
  await step(
    "PUT /v1/files/:name",
    req("/v1/files/3539482a.epub", { method: "PUT", token, body: "epub!" }),
  );
  await step(
    "PUT /v1/files/:name 400 name",
    req("/v1/files/..%2Fescape", { method: "PUT", token, body: "x" }),
  );
  await step(
    "PUT /v1/files/:name 400 length",
    req("/v1/files/3539482a.jpg", {
      method: "PUT",
      token,
      headers: { "content-length": "abc" },
      body: "x",
    }),
  );
  await step(
    "PUT /v1/files/:name 413",
    req("/v1/files/big.epub", {
      method: "PUT",
      token,
      headers: { "content-length": "1073741825" },
      body: "x",
    }),
  );
  await step(
    "PUT /v1/files/:name 401",
    req("/v1/files/3539482a.epub", { method: "PUT", body: "x" }),
  );
  await step(
    "PUT /v1/files/:name 503",
    req("/v1/files/3539482a.epub", { method: "PUT", token, body: "x" }),
    off("BACKUP_ENABLED"),
  );
  await step(
    "POST /v1/files/missing",
    req("/v1/files/missing", {
      method: "POST",
      token,
      body: { names: ["3539482a.epub", "3539482a.jpg"] },
    }),
  );
  await step(
    "POST /v1/files/missing 400",
    req("/v1/files/missing", { method: "POST", token, body: { names: ["../x"] } }),
  );
  await step(
    "POST /v1/files/missing 413",
    req("/v1/files/missing", { method: "POST", token, body: { pad: "x".repeat(257 * 1024) } }),
  );
  await step(
    "POST /v1/files/missing 401",
    req("/v1/files/missing", { method: "POST", body: { names: [] } }),
  );
  await step(
    "POST /v1/files/missing 503",
    req("/v1/files/missing", { method: "POST", token, body: { names: [] } }),
    off("BACKUP_ENABLED"),
  );
  await step(
    "POST /v1/files/missing user limit",
    req("/v1/files/missing", { method: "POST", token, body: { names: [] } }),
    { RATE_LIMITER: denyUser },
  );
  await step("GET /v1/files/:name", req("/v1/files/3539482a.epub", { token }));
  await step("GET /v1/files/:name 404", req("/v1/files/3539482b.epub", { token }));
  await step("GET /v1/files/:name 400", req("/v1/files/..%2Fescape", { token }));
  await step("GET /v1/files/:name 401", req("/v1/files/3539482a.epub"));

  // Backups.
  const manifest = backupsPut.request.headers["x-backup-manifest"];
  await step(
    "PUT /v1/backups",
    req("/v1/backups", {
      method: "PUT",
      token,
      headers: { "x-backup-manifest": manifest },
      body: "zipbytes",
    }),
  );
  await step(
    "PUT /v1/backups 400 manifest",
    req("/v1/backups", {
      method: "PUT",
      token,
      headers: { "x-backup-manifest": "not-json" },
      body: "zipbytes",
    }),
  );
  await step(
    "PUT /v1/backups 401",
    req("/v1/backups", { method: "PUT", headers: { "x-backup-manifest": manifest }, body: "z" }),
  );
  await step(
    "PUT /v1/backups 503",
    req("/v1/backups", {
      method: "PUT",
      token,
      headers: { "x-backup-manifest": manifest },
      body: "z",
    }),
    off("BACKUP_ENABLED"),
  );
  await step(
    "PUT /v1/backups 413",
    req("/v1/backups", {
      method: "PUT",
      token,
      headers: { "x-backup-manifest": manifest, "content-length": "1073741825" },
      body: "z",
    }),
  );
  await step("GET /v1/backups", req("/v1/backups", { token }));
  await step("GET /v1/backups 401", req("/v1/backups"));
  await step("GET /v1/backups 503", req("/v1/backups", { token }), off("BACKUP_ENABLED"));
  await step("GET /v1/backups user limit", req("/v1/backups", { token }), {
    RATE_LIMITER: denyUser,
  });
  // Backup ids come from the upload time; read the one just stored.
  const listed = await callWithBudget(req("/v1/backups", { token }));
  const realId = (await listed.response.json<{ backups: { id: string }[] }>()).backups[0]!.id;
  await step("GET /v1/backups/:id", req(`/v1/backups/${realId}`, { token }));
  await step("GET /v1/backups/:id 404", req("/v1/backups/20000101T000000Z", { token }));
  await step("GET /v1/backups/:id 401", req(`/v1/backups/${realId}`));

  // Sync.
  await step(
    "POST /v1/sync/push",
    req("/v1/sync/push", { method: "POST", token, body: syncPush.request.body }),
  );
  await step(
    "POST /v1/sync/push tombstone",
    req("/v1/sync/push", { method: "POST", token, body: syncPushTombstone.request.body }),
  );
  await step(
    "POST /v1/sync/push older schema",
    req("/v1/sync/push", { method: "POST", token, body: syncPushOlder.request.body }),
  );
  await step(
    "POST /v1/sync/push 400",
    req("/v1/sync/push", { method: "POST", token, body: { records: "nope" } }),
  );
  await step(
    "POST /v1/sync/push 413",
    req("/v1/sync/push", { method: "POST", token, body: { pad: "x".repeat(1024 * 1024) } }),
  );
  await step("POST /v1/sync/push 401", req("/v1/sync/push", { method: "POST", body: {} }));
  await step(
    "POST /v1/sync/push 503",
    req("/v1/sync/push", { method: "POST", token, body: syncPush.request.body }),
    off("SYNC_ENABLED"),
  );
  await step(
    "POST /v1/sync/push user limit",
    req("/v1/sync/push", { method: "POST", token, body: syncPush.request.body }),
    { RATE_LIMITER: denyUser },
  );
  const fresh = structuredClone(syncPush.request.body);
  for (const r of fresh.records) r.key = `${r.key}-quota`;
  await step(
    "POST /v1/sync/push 429 daily writes",
    req("/v1/sync/push", { method: "POST", token, body: fresh }),
    { SYNC_DAILY_WRITES: "1" },
  );
  await step(
    "POST /v1/sync/push 413 storage full",
    req("/v1/sync/push", { method: "POST", token, body: fresh }),
    { SYNC_STORAGE_BYTES: "10" },
  );
  await step("GET /v1/sync/pull", req("/v1/sync/pull?since=0", { token }));
  await step("GET /v1/sync/pull limit", req("/v1/sync/pull?since=1&limit=1", { token }));
  await step("GET /v1/sync/pull empty", req("/v1/sync/pull?since=999", { token }));
  await step("GET /v1/sync/pull 400", req("/v1/sync/pull?since=-1", { token }));
  await step("GET /v1/sync/pull 401", req("/v1/sync/pull?since=0"));
  await step("GET /v1/sync/pull 503", req("/v1/sync/pull?since=0", { token }), off("SYNC_ENABLED"));
  await step("GET /v1/sync/pull user limit", req("/v1/sync/pull?since=0", { token }), {
    RATE_LIMITER: denyUser,
  });

  // Banned AI user, then account deletion (last: it removes the user).
  await createDb(env.DB).update(users).set({ banned: true }).where(eq(users.id, userId));
  await step("POST /v1/ai/key banned", req("/v1/ai/key", { method: "POST", token, body: {} }));
  await step("GET /v1/ai/usage banned", req("/v1/ai/usage", { token }));
  await step("DELETE /v1/me", req("/v1/me", { method: "DELETE", token }));
  await step("GET /v1/me after delete", req("/v1/me", { token }));

  // Legal pages.
  await step("GET /privacy", req("/privacy"));
  await step("GET /account/delete", req("/account/delete"));

  vi.useRealTimers();
  await expect(goldenJson(steps)).toMatchFileSnapshot("./http.golden.json");
});
