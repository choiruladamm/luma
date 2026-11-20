import { env } from "cloudflare:test";
import { eq } from "drizzle-orm";
import { vi } from "vitest";
import { deleteResponse, meResponse } from "@luma/contracts/backend/account";
import { configResponse, keyResponse, usageResponse } from "@luma/contracts/backend/ai";
import { signInResponse, signOutResponse, signUpResponse } from "@luma/contracts/backend/auth";
import { backupInfo, backupsListResponse } from "@luma/contracts/backend/backups";
import { missingResponse, putFileResponse } from "@luma/contracts/backend/files";
import { healthResponse } from "@luma/contracts/backend/health";
import { pullResponse, pushResponse } from "@luma/contracts/backend/sync";
import { z, type ZodType } from "zod";
import { toSnake } from "@luma/worker-kit/case";
import { createDb } from "@luma/core/db/client";
import { users } from "@luma/core/db/schema";
import aiKeyRotateV1 from "@luma/contracts/fixtures/v1/ai-key-rotate.json";
import aiKeyRotateV2 from "@luma/contracts/fixtures/v2/ai-key-rotate.json";
import backupsPutV1 from "@luma/contracts/fixtures/v1/backups-put.json";
import backupsPutV2 from "@luma/contracts/fixtures/v2/backups-put.json";
import signInEmailV1 from "@luma/contracts/fixtures/v1/auth-sign-in-email.json";
import signInEmailV2 from "@luma/contracts/fixtures/v2/auth-sign-in-email.json";
import signInSocialV1 from "@luma/contracts/fixtures/v1/auth-sign-in-social.json";
import signInSocialV2 from "@luma/contracts/fixtures/v2/auth-sign-in-social.json";
import signUpEmailV1 from "@luma/contracts/fixtures/v1/auth-sign-up-email.json";
import signUpEmailV2 from "@luma/contracts/fixtures/v2/auth-sign-up-email.json";
import syncPushOlderV1 from "@luma/contracts/fixtures/v1/sync-push-older-schema.json";
import syncPushOlderV2 from "@luma/contracts/fixtures/v2/sync-push-older-schema.json";
import syncPushTombstoneV1 from "@luma/contracts/fixtures/v1/sync-push-tombstone.json";
import syncPushTombstoneV2 from "@luma/contracts/fixtures/v2/sync-push-tombstone.json";
import syncPushV1 from "@luma/contracts/fixtures/v1/sync-push.json";
import syncPushV2 from "@luma/contracts/fixtures/v2/sync-push.json";
import { createInvite, signUp } from "../helpers/auth";
import { callWithBudget } from "../helpers/budget";
import { GOLDEN_NOW, goldenJson, record, type Recorded } from "../helpers/golden";
import { fakeGoogle, foreignToken } from "../helpers/google";
import { fakeOpenRouter } from "../helpers/openrouter";

/** Success response contract per step; every error response is checked against the shared error body. */
const contracts: Record<string, ZodType> = {
  "GET /v1/health": healthResponse,
  "POST /v1/auth/sign-up/email": signUpResponse,
  "POST /v1/auth/sign-in/email": signInResponse,
  "POST /v1/auth/sign-in/social": signInResponse,
  "POST /v1/auth/sign-out": signOutResponse,
  "GET /v1/me": meResponse,
  "DELETE /v1/me": deleteResponse,
  "POST /v1/ai/key": keyResponse,
  "POST /v1/ai/key rotate": keyResponse,
  "GET /v1/ai/usage": usageResponse,
  "GET /v1/ai/config": configResponse,
  "GET /v1/ai/usage no user limit": usageResponse,
  "GET /v1/ai/config no user limit": configResponse,
  "PUT /v1/files/:name": putFileResponse,
  "POST /v1/files/missing": missingResponse,
  "PUT /v1/backups": backupInfo,
  "GET /v1/backups": backupsListResponse,
  "POST /v1/sync/push": pushResponse,
  "POST /v1/sync/push tombstone": pushResponse,
  "POST /v1/sync/push older schema": pushResponse,
  "GET /v1/sync/pull": pullResponse,
  "GET /v1/sync/pull limit": pullResponse,
  "GET /v1/sync/pull empty": pullResponse,
};

const fixtures = {
  v1: {
    aiKeyRotate: aiKeyRotateV1,
    backupsPut: backupsPutV1,
    signInEmail: signInEmailV1,
    signInSocial: signInSocialV1,
    signUpEmail: signUpEmailV1,
    syncPushOlder: syncPushOlderV1,
    syncPushTombstone: syncPushTombstoneV1,
    syncPush: syncPushV1,
  },
  v2: {
    aiKeyRotate: aiKeyRotateV2,
    backupsPut: backupsPutV2,
    signInEmail: signInEmailV2,
    signInSocial: signInSocialV2,
    signUpEmail: signUpEmailV2,
    syncPushOlder: syncPushOlderV2,
    syncPushTombstone: syncPushTombstoneV2,
    syncPush: syncPushV2,
  },
};

const deny = { limit: async () => ({ success: false }) } as unknown as RateLimit;
/** Denies only the per-user limit, so the request passes the IP limit and reaches the session. */
const denyUser = {
  limit: async ({ key }: { key: string }) => ({ success: !key.startsWith("user:") }),
};
const off = (flag: "SYNC_ENABLED" | "BACKUP_ENABLED" | "AI_KEY_ENABLED") => ({ [flag]: "false" });

type Init = { method?: string; token?: string; headers?: Record<string, string>; body?: unknown };

/** Builds a request; an object body is sent as JSON, a string body as is with its length. */
function build(path: string, { method = "GET", token, headers = {}, body }: Init = {}) {
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

const OPAQUE = ["records.*.data"];

export type Wire = "v1" | "v2";

/**
 * Every backend route with its success and error cases, recorded in full (status, headers, body,
 * D1 queries, subrequests). One scenario runs on both versions: it is written for `/v1` and
 * `req` / `step` move it to the other prefix, while the fixtures and the one inline snake_case
 * body come from `wire`. The `/v1` file must stay byte-identical (the app installs in production
 * speak it); an intended change shows up as a reviewable diff.
 */
export async function records(wire: Wire) {
  const { aiKeyRotate, backupsPut, signInEmail, signInSocial, signUpEmail } = fixtures[wire];
  const { syncPushOlder, syncPushTombstone, syncPush } = fixtures[wire];
  const prefix = (text: string) => text.replace("/v1/", `/${wire}/`);
  const req = (path: string, init?: Init) => build(prefix(path), init);
  // The contracts are snake_case; a v1 response is checked as its snake_case.
  const contractFor = (name: string) => {
    const schema = contracts[name];
    return wire === "v1" && schema ? z.preprocess((v) => toSnake(v, OPAQUE), schema) : schema;
  };
  vi.useFakeTimers({ toFake: ["Date"], now: GOLDEN_NOW });
  const steps: Record<string, Recorded> = {};
  const step = async (name: string, request: Request, overrides: Partial<Env> = {}) => {
    const named = prefix(name);
    steps[named] = await record(request, overrides, contractFor(name)).catch((e: Error) => {
      throw new Error(`${named}: ${e.message}`, { cause: e });
    });
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
        [wire === "v1" ? "idToken" : "id_token"]: {
          token: await google.idToken({ email: "golden@gmail.test", sub: "google-1" }),
        },
      },
    }),
  );
  await step(
    "POST /v1/auth/sign-in/social foreign token",
    req("/v1/auth/sign-in/social", {
      method: "POST",
      body: {
        provider: "google",
        [wire === "v1" ? "idToken" : "id_token"]: { token: await foreignToken() },
      },
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
  await step("GET /v1/ai/usage 429 ip", req("/v1/ai/usage", { token }), { RATE_LIMITER: deny });
  await step("GET /v1/ai/config 429 ip", req("/v1/ai/config", { token }), {
    RATE_LIMITER: deny,
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
  await step(
    "GET /v1/files/:name 503",
    req("/v1/files/3539482a.epub", { token }),
    off("BACKUP_ENABLED"),
  );

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
  await step(
    "GET /v1/backups/:id 503",
    req(`/v1/backups/${realId}`, { token }),
    off("BACKUP_ENABLED"),
  );

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
  return goldenJson(steps);
}
