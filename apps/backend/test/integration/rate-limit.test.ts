import { exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import limited from "../fixtures/contract/error-rate-limited.json";
import { TEST_RATE_LIMIT } from "../helpers/limits";
import { callWithBudget } from "../helpers/budget";

describe("rate limit /v1/*", () => {
  it("answers 429 + Retry-After once the binding says no (contract)", async () => {
    const deny = { limit: async () => ({ success: false }) } as unknown as RateLimit;
    const { response, d1Queries } = await callWithBudget(
      new Request("https://luma.test/v1/health"),
      { RATE_LIMITER: deny },
    );
    expect(response.status).toBe(limited.response.status);
    expect(response.headers.get("Retry-After")).toBe(limited.response.headers["Retry-After"]);
    expect(await response.json()).toEqual(limited.response.body);
    expect(d1Queries).toBe(0);
  });

  // vitest.config.ts naikin limit-nya (60 di wrangler.jsonc): yang dites di sini
  // binding beneran ngitung per IP, bukan angkanya.
  it("enforces the real binding per IP", async () => {
    const hit = () =>
      exports.default.fetch("https://luma.test/v1/health", {
        headers: { "cf-connecting-ip": "10.9.9.9" },
      });
    const statuses: number[] = [];
    for (let i = 0; i <= TEST_RATE_LIMIT; i++) statuses.push((await hit()).status);
    expect(statuses.slice(0, TEST_RATE_LIMIT).every((s) => s === 200)).toBe(true);
    expect(statuses[TEST_RATE_LIMIT]).toBe(429);

    const other = await exports.default.fetch("https://luma.test/v1/health", {
      headers: { "cf-connecting-ip": "10.9.9.10" },
    });
    expect(other.status).toBe(200);
  });
});
