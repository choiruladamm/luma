import { Hono } from "hono";
import { HTTPException } from "hono/http-exception";
import { describe, expect, it, vi } from "vitest";
import type { AppEnv } from "../../src/env";
import { ApiError, onError } from "../../src/lib/errors";

const appThrowing = (err: Error) => {
  const app = new Hono<AppEnv>();
  app.get("/", () => {
    throw err;
  });
  app.onError(onError);
  return app;
};

describe("onError", () => {
  it("renders ApiError with its status, code and headers", async () => {
    const res = await appThrowing(
      new ApiError(429, "RATE_LIMITED", "slow down", { "Retry-After": "60" }),
    ).request("/");
    expect(res.status).toBe(429);
    expect(res.headers.get("Retry-After")).toBe("60");
    expect(await res.json()).toEqual({ error: { code: "RATE_LIMITED", message: "slow down" } });
  });

  it("maps 4xx HTTPException to BAD_REQUEST", async () => {
    const res = await appThrowing(new HTTPException(400, { message: "bad json" })).request("/");
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: { code: "BAD_REQUEST", message: "bad json" } });
  });

  it("hides unknown errors behind 500 INTERNAL_ERROR and logs JSON", async () => {
    const log = vi.spyOn(console, "error").mockImplementation(() => {});
    const res = await appThrowing(new Error("db exploded")).request("/");
    expect(res.status).toBe(500);
    expect(await res.json()).toEqual({ error: { code: "INTERNAL_ERROR", message: "Internal error" } });
    expect(JSON.parse(String(log.mock.calls[0]?.[0]))).toMatchObject({ error: "db exploded" });
    log.mockRestore();
  });
});
