import { env } from "cloudflare:test";
import { exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import futureDay from "@luma/contracts/fixtures/v2/error-usage-future-day.json";
import unauthorized from "@luma/contracts/fixtures/v2/error-unauthorized.json";
import tooLarge from "@luma/contracts/fixtures/v2/error-sync-too-large.json";
import usageV1 from "@luma/contracts/fixtures/v1/usage.json";
import usageFixture from "@luma/contracts/fixtures/v2/usage.json";
import { signUp } from "../helpers/auth";
import { callWithBudget } from "../helpers/budget";
import { expectContract } from "../helpers/contract";

type Row = (typeof usageFixture.request.body.rows)[number];

const post = (token: string | null, body: unknown, version = "v2") =>
  new Request(`https://luma.test/${version}/usage`, {
    method: "POST",
    headers: {
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      "content-type": "application/json",
    },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });

const stored = async (userId: string) =>
  (
    await env.DB.prepare(
      `SELECT day, feature, model, book_key, book_title, key_source, calls, failed, prompt_tokens,
         completion_tokens, cost_usd, reading_seconds FROM usage_daily WHERE user_id = ?
       ORDER BY day, feature, book_key`,
    )
      .bind(userId)
      .all<Row>()
  ).results;

const [group, reading] = usageFixture.request.body.rows as [Row, Row];
const withBook = (i: number): Row => ({ ...group, book_key: `b${i}` });

describe("POST /v2/usage", () => {
  it("stores the rollup rows (contract)", async () => {
    const { token, userId } = await signUp();
    await expectContract(
      await exports.default.fetch(post(token, usageFixture.request.body)),
      usageFixture,
    );
    expect(await stored(userId)).toEqual([group, reading]);
  });

  it("speaks camelCase on /v1 (contract)", async () => {
    const { token, userId } = await signUp();
    await expectContract(
      await exports.default.fetch(post(token, usageV1.request.body, "v1")),
      usageV1,
    );
    expect(await stored(userId)).toEqual([group, reading]);
  });

  it("replaces a resent row instead of adding to it", async () => {
    const { token, userId } = await signUp();
    await exports.default.fetch(post(token, usageFixture.request.body));
    const updated = { ...group, calls: 15, cost_usd: null };
    const res = await exports.default.fetch(post(token, { rows: [updated, updated] }));
    expect(await res.json()).toEqual({ applied: 2 });
    expect(await stored(userId)).toEqual([updated, reading]);
  });

  it("rejects days in the future (contract)", async () => {
    const { token, userId } = await signUp();
    const res = await exports.default.fetch(
      post(token, { rows: [reading, { ...group, day: "2099-01-01" }] }),
    );
    await expectContract(res, futureDay);
    expect(await stored(userId)).toEqual([]);
  });

  it("rejects bad bodies", async () => {
    const { token } = await signUp();
    const bad = [
      "not json",
      { rows: [] },
      { rows: Array.from({ length: 501 }, (_, i) => withBook(i)) },
      { rows: [{ ...group, feature: "tts" }] },
      { rows: [{ ...group, day: "12/11/2026" }] },
      { rows: [{ ...group, key_source: null }] },
      { rows: [{ ...group, calls: -1 }] },
      { rows: [group], extra: 1 },
    ];
    for (const body of bad) {
      expect((await exports.default.fetch(post(token, body))).status, JSON.stringify(body)).toBe(
        400,
      );
    }
  });

  it("refuses bodies over 1MB before parsing (contract)", async () => {
    const { token } = await signUp();
    const big = JSON.stringify({ rows: [{ ...group, book_title: "x".repeat(1024 * 1024) }] });
    const res = await exports.default.fetch(post(token, big));
    expect(res.status).toBe(413);
    expect((await res.json<{ error: { code: string } }>()).error.code).toBe(
      tooLarge.response.body.error.code,
    );
  });

  it("keeps each user's rows apart", async () => {
    const a = await signUp();
    const b = await signUp();
    await exports.default.fetch(post(a.token, { rows: [group] }));
    await exports.default.fetch(post(b.token, { rows: [{ ...group, calls: 1 }] }));
    expect((await stored(a.userId))[0]?.calls).toBe(12);
    expect((await stored(b.userId))[0]?.calls).toBe(1);
  });

  it("needs a session (contract)", async () => {
    await expectContract(await exports.default.fetch(post(null, {})), unauthorized);
    const bad = await exports.default.fetch(post("not-a-token", usageFixture.request.body));
    expect(bad.status).toBe(401);
  });

  it("is rate limited per user", async () => {
    const { token } = await signUp();
    const denyUser = {
      limit: async ({ key }: { key: string }) => ({ success: !key.startsWith("user:") }),
    };
    const { response } = await callWithBudget(post(token, usageFixture.request.body), {
      RATE_LIMITER: denyUser,
    });
    expect(response.status).toBe(429);
  });

  it("refuses rows past the daily quota until UTC midnight, without writing", async () => {
    const { token, userId } = await signUp();
    for (let batch = 0; batch < 4; batch++) {
      const rows = Array.from({ length: 500 }, (_, i) => withBook(batch * 500 + i));
      expect((await exports.default.fetch(post(token, { rows }))).status).toBe(200);
    }

    const res = await exports.default.fetch(post(token, { rows: [withBook(9999)] }));

    expect(res.status).toBe(429);
    expect(await res.json()).toEqual({
      error: { code: "QUOTA_EXCEEDED", message: "Daily usage quota reached" },
    });
    const retryAfter = Number(res.headers.get("retry-after"));
    expect(retryAfter).toBeGreaterThan(0);
    expect(retryAfter).toBeLessThanOrEqual(24 * 60 * 60);
    expect(await stored(userId)).toHaveLength(2000);
  });

  it("stays inside the budget: 500 rows = session + quota read + 1 batch", async () => {
    const { token } = await signUp();
    const rows = Array.from({ length: 500 }, (_, i) => withBook(i));
    const { response, d1Queries, subrequests } = await callWithBudget(post(token, { rows }));
    expect(await response.json()).toEqual({ applied: 500 });
    expect(subrequests).toBe(0);
    // session (≤2) + quota SELECT + 2-statement batch
    expect(d1Queries).toBeLessThanOrEqual(5);
  });
});
