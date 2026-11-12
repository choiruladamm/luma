import { exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import health from "../fixtures/contract/health.json";
import { callWithBudget } from "../helpers/budget";

const url = (path: string) => `https://luma.test${path}`;

describe("GET /v1/health", () => {
  it("matches the contract fixture", async () => {
    const res = await exports.default.fetch(url(health.request.path), {
      headers: { "cf-connecting-ip": "10.0.0.1" },
    });
    expect(res.status).toBe(health.response.status);
    expect(await res.json()).toEqual(health.response.body);
    expect(res.headers.get("x-request-id")).toMatch(/^[0-9a-f-]{36}$/);
  });

  it("stays inside the budget: no D1 query, no subrequest", async () => {
    const { response, d1Queries, subrequests } = await callWithBudget(
      new Request(url("/v1/health"), { headers: { "cf-connecting-ip": "10.0.0.2" } }),
    );
    expect(response.status).toBe(200);
    expect(d1Queries).toBe(0);
    expect(subrequests).toBe(0);
  });

  it("returns the uniform error body for unknown routes", async () => {
    const res = await exports.default.fetch(url("/v1/nope"), {
      headers: { "cf-connecting-ip": "10.0.0.3" },
    });
    expect(res.status).toBe(404);
    expect(await res.json()).toEqual({ error: { code: "NOT_FOUND", message: "Not found" } });
  });
});
