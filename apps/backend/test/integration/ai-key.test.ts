import { env } from "cloudflare:test";
import { exports } from "cloudflare:workers";
import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { createDb } from "../../src/db/client";
import { users } from "../../src/db/schema";
import aiConfigFixture from "../fixtures/contract/ai-config.json";
import aiKeyRotate from "../fixtures/contract/ai-key-rotate.json";
import aiKey from "../fixtures/contract/ai-key.json";
import aiUsage from "../fixtures/contract/ai-usage.json";
import aiBanned from "../fixtures/contract/error-ai-banned.json";
import bannedUsage from "../fixtures/contract/error-ai-banned-usage.json";
import disabled from "../fixtures/contract/error-service-disabled.json";
import unauthorized from "../fixtures/contract/error-unauthorized.json";
import { signUp } from "../helpers/auth";
import { callWithBudget } from "../helpers/budget";
import { expectContract } from "../helpers/contract";
import { fakeOpenRouter } from "../helpers/openrouter";

const url = (path: string) => `https://luma.test${path}`;
const bearer = (token: string) => ({ authorization: `Bearer ${token}` });
const postKey = (token: string, body: unknown = {}) =>
  new Request(url("/v1/ai/key"), {
    method: "POST",
    headers: { ...bearer(token), "content-type": "application/json" },
    body: JSON.stringify(body),
  });

describe("POST /v1/ai/key", () => {
  it("creates a key in the subsidy workspace on first use (contract)", async () => {
    const or = fakeOpenRouter();
    const { token } = await signUp();

    const body = (await expectContract(await exports.default.fetch(postKey(token)), aiKey)) as {
      key: string;
    };

    expect(or.calls).toEqual(["POST /keys"]);
    const created = [...or.keys.values()][0]!;
    expect(created).toMatchObject({ key: body.key, limit: 0.02, workspaceId: env.OPENROUTER_WORKSPACE_ID });
  });

  it("hands every device of a user the same key; users never share", async () => {
    const or = fakeOpenRouter();
    const a = await signUp();
    const b = await signUp();

    const a1 = (await (await exports.default.fetch(postKey(a.token))).json()) as { key: string };
    const a2 = (await (await exports.default.fetch(postKey(a.token))).json()) as { key: string };
    const b1 = (await (await exports.default.fetch(postKey(b.token))).json()) as { key: string };

    expect(a2.key).toBe(a1.key);
    expect(b1.key).not.toBe(a1.key);
    expect(or.calls.filter((c) => c === "POST /keys")).toHaveLength(2);
  });

  it("rotates on request after the app got a 401 (contract)", async () => {
    const or = fakeOpenRouter();
    const { token } = await signUp();
    const first = (await (await exports.default.fetch(postKey(token))).json()) as { key: string };

    const res = await exports.default.fetch(postKey(token, aiKeyRotate.request.body));
    const body = (await expectContract(res, aiKeyRotate)) as { key: string };

    expect(body.key).not.toBe(first.key);
    expect(or.calls).toEqual(["POST /keys", "DELETE /keys/hash-1", "POST /keys"]);
    expect(or.keys.size).toBe(1);
  });

  it("refuses banned users (contract)", async () => {
    fakeOpenRouter();
    const { token, userId } = await signUp();
    await createDb(env.DB).update(users).set({ banned: true }).where(eq(users.id, userId));

    await expectContract(await exports.default.fetch(postKey(token)), aiBanned);
  });

  it("requires a session (contract)", async () => {
    const res = await exports.default.fetch(url("/v1/ai/key"), { method: "POST", body: "{}" });
    await expectContract(res, unauthorized);
  });

  it("rejects unknown fields and oversized bodies", async () => {
    const { token } = await signUp();
    expect((await exports.default.fetch(postKey(token, { rotate: "ya" }))).status).toBe(400);
    expect((await exports.default.fetch(postKey(token, { extra: 1 }))).status).toBe(400);
    expect((await exports.default.fetch(postKey(token, { pad: "x".repeat(2000) }))).status).toBe(413);
  });

  it("answers 503 without touching D1 or OpenRouter when switched off", async () => {
    const { token } = await signUp();
    const { response, d1Queries, subrequests } = await callWithBudget(postKey(token), {
      AI_KEY_ENABLED: "false",
    });
    expect(response.status).toBe(503);
    expect((await response.json()) as unknown).toEqual({
      error: { ...disabled.response.body.error, message: "AI_KEY_ENABLED is off" },
    });
    expect(d1Queries).toBe(0);
    expect(subrequests).toBe(0);
  });

  it("is rate limited per user", async () => {
    const { token } = await signUp();
    const deny = { limit: async () => ({ success: false }) } as unknown as RateLimit;
    const { response } = await callWithBudget(postKey(token), { RATE_LIMITER: deny });
    expect(response.status).toBe(429);
  });

  it("stays inside the budget: reuse = 0 subrequests, create = 1", async () => {
    fakeOpenRouter();
    const { token } = await signUp();

    const create = await callWithBudget(postKey(token));
    expect(create.response.status).toBe(200);
    expect(create.subrequests).toBe(1);
    expect(create.d1Queries).toBeLessThanOrEqual(3);

    const reuse = await callWithBudget(postKey(token));
    expect(reuse.subrequests).toBe(0);
    expect(reuse.d1Queries).toBeLessThanOrEqual(2);
  });
});

describe("GET /v1/ai/usage", () => {
  it("reports today's remaining quota from OpenRouter (contract)", async () => {
    const or = fakeOpenRouter();
    const { token } = await signUp();
    await exports.default.fetch(postKey(token));
    [...or.keys.values()][0]!.usageDaily = 0.005;

    const res = await exports.default.fetch(url(aiUsage.request.path), { headers: bearer(token) });
    await expectContract(res, aiUsage);
  });
});

describe("GET /v1/ai/usage when banned", () => {
  it("answers 403 AI_BANNED so the meter shows \"Dicabut\" (contract)", async () => {
    fakeOpenRouter();
    const { token, userId } = await signUp();
    await createDb(env.DB).update(users).set({ banned: true }).where(eq(users.id, userId));

    const res = await exports.default.fetch(url(bannedUsage.request.path), { headers: bearer(token) });
    await expectContract(res, bannedUsage);
  });
});

describe("GET /v1/ai/config", () => {
  it("lists the models the subsidy guardrail allows (contract)", async () => {
    const { token } = await signUp();
    const res = await exports.default.fetch(url(aiConfigFixture.request.path), { headers: bearer(token) });
    await expectContract(res, aiConfigFixture);
  });
});

describe("DELETE /v1/me", () => {
  it("revokes the user's OpenRouter key", async () => {
    const or = fakeOpenRouter();
    const { token } = await signUp();
    await exports.default.fetch(postKey(token));

    const res = await exports.default.fetch(url("/v1/me"), { method: "DELETE", headers: bearer(token) });

    expect(res.status).toBe(200);
    expect(or.keys.size).toBe(0);
  });
});
