import { HttpResponse, http } from "msw";
import { describe, expect, it } from "vitest";
import { network } from "../setup";

describe("outbound fetch guard", () => {
  it("fails loudly for fetches nobody mocked", async () => {
    const res = await fetch("https://unmocked.example/x");
    expect(res.status).toBe(599);
    expect(await res.json()).toMatchObject({ error: { code: "UNMOCKED_FETCH" } });
  });

  it("lets a test mock a specific endpoint", async () => {
    network.use(http.get("https://openrouter.ai/api/v1/key", () => HttpResponse.json({ ok: 1 })));
    const res = await fetch("https://openrouter.ai/api/v1/key");
    expect(await res.json()).toEqual({ ok: 1 });
  });
});
