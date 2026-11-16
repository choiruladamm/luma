import { env } from "cloudflare:test";
import { exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import serviceDisabled from "../fixtures/contract/error-service-disabled.json";
import unauthorized from "../fixtures/contract/error-unauthorized.json";
import pullEmpty from "../fixtures/contract/sync-pull-empty.json";
import pullNewer from "../fixtures/contract/sync-pull-newer-schema.json";
import pullTombstone from "../fixtures/contract/sync-pull-tombstone.json";
import pullFixture from "../fixtures/contract/sync-pull.json";
import tombstone from "../fixtures/contract/sync-push-tombstone.json";
import pushFixture from "../fixtures/contract/sync-push.json";
import { signUp } from "../helpers/auth";
import { callWithBudget } from "../helpers/budget";
import { expectContract } from "../helpers/contract";

const push = (token: string, body: unknown) =>
  new Request("https://luma.test/v1/sync/push", {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify(body),
  });

const setting = (value: string, updatedAt: string) => ({
  kind: "setting",
  key: "ai.model",
  updatedAt,
  deleted: false,
  data: { value },
});

const pull = (token: string, query: string) =>
  new Request(`https://luma.test/v1/sync/pull${query}`, { headers: { authorization: `Bearer ${token}` } });
const path = (f: { request: { path: string } }) => f.request.path.replace("/v1/sync/pull", "");

describe("GET /v1/sync/pull", () => {
  it("returns records after the cursor in seq order (contract)", async () => {
    const { token } = await signUp();
    await exports.default.fetch(push(token, pushFixture.request.body));
    await expectContract(await exports.default.fetch(pull(token, path(pullFixture))), pullFixture);
    await expectContract(await exports.default.fetch(pull(token, path(pullEmpty))), pullEmpty);
  });

  it("carries tombstones (contract)", async () => {
    const { token } = await signUp();
    await exports.default.fetch(push(token, pushFixture.request.body));
    await exports.default.fetch(push(token, tombstone.request.body));
    await expectContract(await exports.default.fetch(pull(token, path(pullTombstone))), pullTombstone);
  });

  it("hands newer-schema records through as-is for the client to hold (contract)", async () => {
    const { token } = await signUp();
    const rec = (pullNewer.response.body.records as Record<string, unknown>[])[0]!;
    await exports.default.fetch(
      push(token, {
        schemaVersion: 19,
        records: [{ kind: rec.kind, key: rec.key, updatedAt: rec.updatedAt, deleted: false, data: rec.data }],
      }),
    );
    await expectContract(await exports.default.fetch(pull(token, path(pullNewer))), pullNewer);
  });

  it("pages with limit and walks the cursor to the end", async () => {
    const { token } = await signUp();
    await exports.default.fetch(push(token, pushFixture.request.body));
    const first = (await (await exports.default.fetch(pull(token, "?since=0&limit=2"))).json()) as {
      records: { seq: number }[];
      nextSeq: number;
      more: boolean;
    };
    expect(first.records.map((r) => r.seq)).toEqual([1, 2]);
    expect(first).toMatchObject({ nextSeq: 2, more: true });
    const second = (await (await exports.default.fetch(pull(token, "?since=2&limit=2"))).json()) as {
      records: { seq: number }[];
      more: boolean;
    };
    expect(second.records.map((r) => r.seq)).toEqual([3]);
    expect(second.more).toBe(false);
  });

  it("rejects a missing or bad cursor and limit", async () => {
    const { token } = await signUp();
    for (const q of ["", "?since=-1", "?since=abc", "?since=0&limit=0", "?since=0&limit=501"]) {
      expect((await exports.default.fetch(pull(token, q))).status).toBe(400);
    }
  });

  it("never shows one user's records to another", async () => {
    const a = await signUp();
    const b = await signUp();
    await exports.default.fetch(push(a.token, pushFixture.request.body));
    expect(await (await exports.default.fetch(pull(b.token, "?since=0"))).json()).toEqual({
      records: [],
      nextSeq: 0,
      more: false,
    });
  });

  it("needs a session, honours the kill switch and the rate limit (contract)", async () => {
    await expectContract(await exports.default.fetch("https://luma.test/v1/sync/pull?since=0"), unauthorized);
    const { token } = await signUp();
    const off = await callWithBudget(pull(token, "?since=0"), { SYNC_ENABLED: "false" });
    await expectContract(off.response, serviceDisabled);
    expect(off.d1Queries).toBe(0);
    const deny = { limit: async () => ({ success: false }) } as unknown as RateLimit;
    expect((await callWithBudget(pull(token, "?since=0"), { RATE_LIMITER: deny })).response.status).toBe(429);
  });

  it("stays inside the budget: one indexed query per page", async () => {
    const { token } = await signUp();
    const records = Array.from({ length: 500 }, (_, i) => ({ ...setting(`m${i}`, "2026-11-13T10:00:00.000Z"), key: `k${i}` }));
    await exports.default.fetch(push(token, { schemaVersion: 18, records }));
    const { response, d1Queries, subrequests } = await callWithBudget(pull(token, "?since=0"));
    const body = (await response.json()) as { records: unknown[]; more: boolean };
    expect(body.records).toHaveLength(500);
    expect(body.more).toBe(false);
    expect(subrequests).toBe(0);
    expect(d1Queries).toBeLessThanOrEqual(3); // sesi (≤2) + 1 pull
    const plan = await env.DB.prepare(
      "EXPLAIN QUERY PLAN SELECT seq FROM records WHERE user_id = ?1 AND seq > ?2 ORDER BY seq LIMIT 501",
    )
      .bind("x", 0)
      .all<{ detail: string }>();
    expect(plan.results.map((r) => r.detail).join(" ")).toContain("records_user_seq");
  });
});
