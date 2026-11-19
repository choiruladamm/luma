import { Hono } from "hono";
import { describe, expect, it, vi } from "vitest";
import { z } from "zod";
import { workerApp } from "../src/app";
import { errorBody } from "../src/errors";
import { log } from "../src/log";
import { killSwitch, limitBody, rateLimit, validate } from "../src/middleware";

type Bindings = { LIMITER: RateLimit; FEATURE: string };
const limiter = (success: boolean) => {
  const limit = vi.fn<RateLimit["limit"]>(async () => ({ success }));
  return { limit } as RateLimit & { limit: typeof limit };
};
const post = (body: string, headers: Record<string, string> = {}) => ({
  method: "POST",
  body,
  headers: { "content-type": "application/json", ...headers },
});
const limitedApp = (key: string | null) =>
  workerApp(new Hono<{ Bindings: Bindings }>()).get(
    "/",
    rateLimit<{ Bindings: Bindings }>({
      limiter: (c) => c.env.LIMITER,
      key: () => key,
      periodSeconds: 42,
    }),
    (c) => c.text("ok"),
  );

describe("rateLimit", () => {
  const app = limitedApp;

  it("lets a request under the limit through and checks its key", async () => {
    const LIMITER = limiter(true);
    const res = await app("user:1").request("/", {}, { LIMITER, FEATURE: "true" });
    expect(res.status).toBe(200);
    expect(LIMITER.limit).toHaveBeenCalledWith({ key: "user:1" });
  });

  it("answers 429 with Retry-After over the limit", async () => {
    const res = await app("user:1").request("/", {}, { LIMITER: limiter(false), FEATURE: "" });
    expect(res.status).toBe(429);
    expect(res.headers.get("retry-after")).toBe("42");
    expect(await res.json()).toEqual(errorBody("RATE_LIMITED", "Too many requests"));
  });

  it("skips the check for a null key", async () => {
    const LIMITER = limiter(false);
    const res = await app(null).request("/", {}, { LIMITER, FEATURE: "" });
    expect(res.status).toBe(200);
    expect(LIMITER.limit).not.toHaveBeenCalled();
  });
});

describe("killSwitch", () => {
  const app = workerApp(new Hono<{ Bindings: Bindings }>()).get(
    "/",
    killSwitch("FEATURE", 7),
    (c) => c.text("ok"),
  );

  it("passes only when the var is the string true", async () => {
    const env = { LIMITER: limiter(true) };
    expect((await app.request("/", {}, { ...env, FEATURE: "true" })).status).toBe(200);
    for (const FEATURE of ["false", "TRUE", ""]) {
      const res = await app.request("/", {}, { ...env, FEATURE });
      expect(res.status).toBe(503);
      expect(res.headers.get("retry-after")).toBe("7");
      expect(await res.json()).toEqual(errorBody("SERVICE_DISABLED", "FEATURE is off"));
    }
  });
});

describe("limitBody", () => {
  const app = workerApp(new Hono()).post("/", limitBody(10), (c) => c.text("ok"));

  it("accepts a body within the limit and rejects a larger one with 413", async () => {
    expect((await app.request("/", post("{}"))).status).toBe(200);
    const res = await app.request("/", post('{"a":"0123456789"}'));
    expect(res.status).toBe(413);
    expect(await res.json()).toEqual(errorBody("PAYLOAD_TOO_LARGE", "Body exceeds 10 bytes"));
  });
});

describe("validate", () => {
  const schema = z.object({ n: z.number({ error: "n must be a number" }) });
  const app = workerApp(new Hono())
    .post("/default", validate("json", schema), (c) => c.json(c.req.valid("json")))
    .post("/message", validate("json", schema, "Body must be {n}"), (c) => c.text("ok"))
    .post(
      "/per-request",
      validate("json", schema, (c) => `Body for ${c.req.path}`),
      (c) => c.text("ok"),
    );

  it("passes the parsed value to the handler", async () => {
    const res = await app.request("/default", post('{"n":1}'));
    expect(await res.json()).toEqual({ n: 1 });
  });

  it("answers 400 with the first zod issue, or the route's message", async () => {
    const plain = await app.request("/default", post('{"n":"x"}'));
    expect(await plain.json()).toEqual(errorBody("BAD_REQUEST", "n must be a number"));
    const custom = await app.request("/message", post('{"n":"x"}'));
    expect(custom.status).toBe(400);
    expect(await custom.json()).toEqual(errorBody("BAD_REQUEST", "Body must be {n}"));
    const perRequest = await app.request("/per-request", post('{"n":"x"}'));
    expect(await perRequest.json()).toEqual(errorBody("BAD_REQUEST", "Body for /per-request"));
  });
});

describe("log", () => {
  it("writes one JSON line per level with the message first", () => {
    const spies = {
      error: vi.spyOn(console, "error").mockImplementation(() => {}),
      warn: vi.spyOn(console, "warn").mockImplementation(() => {}),
      info: vi.spyOn(console, "log").mockImplementation(() => {}),
    };
    log.error("e", { requestId: "r", n: 1 });
    log.warn("w", { requestId: "r" });
    log.info("i", { requestId: "r" });
    expect(spies.error).toHaveBeenCalledWith('{"message":"e","requestId":"r","n":1}');
    expect(spies.warn).toHaveBeenCalledWith('{"message":"w","requestId":"r"}');
    expect(spies.info).toHaveBeenCalledWith('{"message":"i","requestId":"r"}');
    for (const spy of Object.values(spies)) spy.mockRestore();
  });
});
