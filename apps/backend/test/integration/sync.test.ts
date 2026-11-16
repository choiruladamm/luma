import { env } from "cloudflare:test";
import { exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import badRequest from "../fixtures/contract/error-sync-bad-request.json";
import serviceDisabled from "../fixtures/contract/error-service-disabled.json";
import tooLarge from "../fixtures/contract/error-sync-too-large.json";
import unauthorized from "../fixtures/contract/error-unauthorized.json";
import olderSchema from "../fixtures/contract/sync-push-older-schema.json";
import tombstone from "../fixtures/contract/sync-push-tombstone.json";
import pushFixture from "../fixtures/contract/sync-push.json";
import { signUp } from "../helpers/auth";
import { callWithBudget } from "../helpers/budget";
import { expectContract } from "../helpers/contract";

type Row = { kind: string; key: string; data: string | null; deleted: number; seq: number; schema_version: number };

const push = (token: string, body: unknown) =>
  new Request("https://luma.test/v1/sync/push", {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });

const rows = async (userId: string) =>
  (
    await env.DB.prepare("SELECT * FROM records WHERE user_id = ? ORDER BY seq").bind(userId).all<Row>()
  ).results;

const setting = (value: string, updatedAt: string) => ({
  kind: "setting",
  key: "ai.model",
  updatedAt,
  deleted: false,
  data: { value },
});

describe("POST /v1/sync/push", () => {
  it("stores records with increasing seq (contract)", async () => {
    const { token, userId } = await signUp();
    await expectContract(await exports.default.fetch(push(token, pushFixture.request.body)), pushFixture);

    const stored = await rows(userId);
    expect(stored.map((r) => [r.kind, r.key, r.seq])).toEqual([
      ["book", "3539482a", 1],
      ["reading_progress", "3539482a", 2],
      ["ai_result", "3539482a/4/12", 3],
    ]);
    expect(JSON.parse(stored[0]!.data!).title).toBe("Meditations");
    expect(stored[0]!.schema_version).toBe(18);
  });

  it("stores a tombstone and bumps seq only for what changed (contract)", async () => {
    const { token, userId } = await signUp();
    await exports.default.fetch(push(token, pushFixture.request.body));
    // Push ulang yang sama persis: gak nulis, seq tetap.
    const again = await exports.default.fetch(push(token, pushFixture.request.body));
    expect(await again.json()).toEqual({ seq: 3, applied: 0 });

    await expectContract(await exports.default.fetch(push(token, tombstone.request.body)), tombstone);
    const book = (await rows(userId)).find((r) => r.kind === "book")!;
    expect(book).toMatchObject({ deleted: 1, data: null, seq: 4 });
  });

  it("holds newer-schema records against an older app (contract)", async () => {
    const { token, userId } = await signUp();
    await exports.default.fetch(push(token, pushFixture.request.body));
    await expectContract(await exports.default.fetch(push(token, olderSchema.request.body)), olderSchema);
    const progress = (await rows(userId)).find((r) => r.kind === "reading_progress")!;
    expect(JSON.parse(progress.data!).paragraphIndex).toBe(37);
  });

  it("last write wins per key, inside one batch too", async () => {
    const { token, userId } = await signUp();
    await exports.default.fetch(
      push(token, {
        schemaVersion: 18,
        records: [setting("b", "2026-11-13T10:00:02.000Z"), setting("a", "2026-11-13T10:00:01.000Z")],
      }),
    );
    let [row] = await rows(userId);
    expect(JSON.parse(row!.data!).value).toBe("b");

    await exports.default.fetch(push(token, { schemaVersion: 18, records: [setting("old", "2026-01-01T00:00:00.000Z")] }));
    [row] = await rows(userId);
    expect(JSON.parse(row!.data!).value).toBe("b");
  });

  it("rejects bad bodies (contract)", async () => {
    const { token } = await signUp();
    await expectContract(await exports.default.fetch(push(token, badRequest.request.body)), badRequest);
    const bad = [
      "not json",
      { schemaVersion: 18, records: Array(501).fill(setting("a", "2026-11-13T10:00:00.000Z")) },
      { schemaVersion: 18, records: [{ ...setting("a", "2026-11-13T10:00:00.000Z"), kind: "users" }] },
      { schemaVersion: 18, records: [{ ...setting("a", "kemarin") }] },
      { schemaVersion: 18, records: [{ ...setting("a", "2026-11-13T10:00:00.000Z"), data: null }] },
      { schemaVersion: 18, records: [setting("a", "2026-11-13T10:00:00.000Z")], extra: 1 },
    ];
    for (const body of bad) {
      expect((await exports.default.fetch(push(token, body))).status).toBe(400);
    }
  });

  it("refuses bodies over 1MB before parsing (contract)", async () => {
    const { token } = await signUp();
    const big = JSON.stringify({ schemaVersion: 18, records: [setting("x".repeat(1024 * 1024), "2026-11-13T10:00:00.000Z")] });
    await expectContract(await exports.default.fetch(push(token, big)), tooLarge);
  });

  it("keeps each user's records apart", async () => {
    const a = await signUp();
    const b = await signUp();
    await exports.default.fetch(push(a.token, pushFixture.request.body));
    const res = await exports.default.fetch(push(b.token, pushFixture.request.body));
    expect(await res.json()).toEqual({ seq: 3, applied: 3 });
    expect(await rows(b.userId)).toHaveLength(3);
    expect(await rows(a.userId)).toHaveLength(3);
  });

  it("needs a session (contract)", async () => {
    await expectContract(
      await exports.default.fetch("https://luma.test/v1/sync/push", { method: "POST" }),
      unauthorized,
    );
  });

  it("answers 503 without touching D1 when sync is switched off (contract)", async () => {
    const { token } = await signUp();
    const { response, d1Queries } = await callWithBudget(push(token, pushFixture.request.body), {
      SYNC_ENABLED: "false",
    });
    await expectContract(response, serviceDisabled);
    expect(d1Queries).toBe(0);
  });

  it("is rate limited per user", async () => {
    const { token } = await signUp();
    const deny = { limit: async () => ({ success: false }) } as unknown as RateLimit;
    const { response } = await callWithBudget(push(token, pushFixture.request.body), { RATE_LIMITER: deny });
    expect(response.status).toBe(429);
  });

  it("refuses writes past the daily quota until UTC midnight, without writing", async () => {
    const { token, userId } = await signUp();
    const limits = { SYNC_DAILY_WRITES: "3" };
    const first = await callWithBudget(push(token, pushFixture.request.body), limits);
    expect(first.response.status).toBe(200);

    const { response } = await callWithBudget(
      push(token, { schemaVersion: 18, records: [{ ...setting("x", "2026-11-13T10:00:00.000Z"), key: "baru" }] }),
      limits,
    );

    expect(response.status).toBe(429);
    expect(await response.json()).toEqual({ error: { code: "QUOTA_EXCEEDED", message: "Daily sync quota reached" } });
    const retryAfter = Number(response.headers.get("retry-after"));
    expect(retryAfter).toBeGreaterThan(0);
    expect(retryAfter).toBeLessThanOrEqual(24 * 60 * 60);
    expect(await rows(userId)).toHaveLength(3);
  });

  it("tracks stored sync size exactly and refuses growth past the storage quota", async () => {
    const { token, userId } = await signUp();
    const storedSize = async () => {
      const usage = await env.DB.prepare("SELECT sync_bytes AS b FROM user_storage WHERE user_id = ?").bind(userId).first<{ b: number }>();
      const real = await env.DB.prepare(
        "SELECT sum(length(key) + coalesce(length(data), 0)) AS b FROM records WHERE user_id = ?",
      )
        .bind(userId)
        .first<{ b: number }>();
      expect(usage?.b).toBe(real?.b);
      return usage!.b;
    };
    const send = (value: string, updatedAt: string, limit = "1000") =>
      callWithBudget(push(token, { schemaVersion: 18, records: [setting(value, updatedAt)] }), {
        SYNC_STORAGE_BYTES: limit,
      });

    expect((await send("a".repeat(100), "2026-11-13T10:00:00.000Z")).response.status).toBe(200);
    const afterFirst = await storedSize();
    expect((await send("b".repeat(10), "2026-11-13T10:01:00.000Z")).response.status).toBe(200);
    expect(await storedSize()).toBe(afterFirst - 90);

    const full = await send("c".repeat(2000), "2026-11-13T10:02:00.000Z");
    expect(full.response.status).toBe(413);
    expect(await full.response.json()).toEqual({ error: { code: "STORAGE_FULL", message: "Sync storage is full" } });

    // Udah lewat kuota (kuota diturunin): yang mengecilkan data tetap boleh.
    expect((await send("d", "2026-11-13T10:03:00.000Z", "1")).response.status).toBe(200);
    await storedSize();
  });

  it("stays inside the budget: 500 records = session + 1 read + quota + 1 batch", async () => {
    const { token } = await signUp();
    const records = Array.from({ length: 500 }, (_, i) => ({
      ...setting(`m${i}`, "2026-11-13T10:00:00.000Z"),
      key: `k${i}`,
    }));
    const { response, d1Queries, subrequests } = await callWithBudget(push(token, { schemaVersion: 18, records }));
    expect(await response.json()).toEqual({ seq: 500, applied: 500 });
    expect(subrequests).toBe(0);
    // sesi (≤2) + SELECT lama + kuota + batch 2 statement
    expect(d1Queries).toBeLessThanOrEqual(6);
  });
});
