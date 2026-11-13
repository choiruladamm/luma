import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { push } from "../../src/features/sync/service";
import { signUp } from "../helpers/auth";

const limits = { storageBytes: 1_000_000, dailyWrites: 2 };
const record = (key: string) => ({
  kind: "setting" as const,
  key,
  updatedAt: "2026-11-13T10:00:00.000Z",
  deleted: false,
  data: { value: key },
});

describe("sync daily quota", () => {
  it("counts rows per UTC day and starts over the next day", async () => {
    const { userId } = await signUp();
    const today = new Date("2026-11-13T23:59:00Z");
    await push(env.DB, userId, { schemaVersion: 18, records: [record("a"), record("b")] }, limits, today);

    await expect(push(env.DB, userId, { schemaVersion: 18, records: [record("c")] }, limits, today)).rejects.toMatchObject({
      status: 429,
      code: "QUOTA_EXCEEDED",
      headers: { "Retry-After": "60" },
    });

    const tomorrow = new Date("2026-11-14T00:00:01Z");
    expect(await push(env.DB, userId, { schemaVersion: 18, records: [record("c")] }, limits, tomorrow)).toEqual({
      seq: 3,
      applied: 1,
    });
  });

  it("does not count pushes that change nothing", async () => {
    const { userId } = await signUp();
    const now = new Date("2026-11-13T10:00:00Z");
    const body = { schemaVersion: 18, records: [record("a"), record("b")] };
    await push(env.DB, userId, body, limits, now);

    expect(await push(env.DB, userId, body, limits, now)).toEqual({ seq: 2, applied: 0 });
  });
});
