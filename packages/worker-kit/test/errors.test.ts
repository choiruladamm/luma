import { Hono } from "hono";
import { HTTPException } from "hono/http-exception";
import { describe, expect, it, vi } from "vitest";
import { workerApp } from "../src/app";
import { ApiError, codeForStatus, errorBody, normalizeAuthError } from "../src/errors";

const json = (status: number, body: unknown) =>
  Response.json(body, { status, headers: { "set-cookie": "a=b" } });

const appThrowing = (err: Error) => {
  const app = workerApp(new Hono());
  app.get("/", () => {
    throw err;
  });
  return app;
};

describe("onError", () => {
  it("renders an ApiError with its status, code, and headers", async () => {
    const res = await appThrowing(
      new ApiError(429, "RATE_LIMITED", "Too many requests", { "Retry-After": "60" }),
    ).request("/");
    expect(res.status).toBe(429);
    expect(res.headers.get("retry-after")).toBe("60");
    expect(await res.json()).toEqual(errorBody("RATE_LIMITED", "Too many requests"));
  });

  it.each([
    [400, "BAD_REQUEST"],
    [401, "UNAUTHORIZED"],
    [403, "FORBIDDEN"],
    [404, "NOT_FOUND"],
    [413, "PAYLOAD_TOO_LARGE"],
    [429, "RATE_LIMITED"],
    [422, "BAD_REQUEST"],
  ] as const)("maps a %i HTTPException to %s", async (status, code) => {
    const res = await appThrowing(new HTTPException(status, { message: "nope" })).request("/");
    expect(res.status).toBe(status);
    expect(await res.json()).toEqual(errorBody(code, "nope"));
  });

  it("keeps an HTTPException's own headers and fills an empty message", async () => {
    const res = await appThrowing(
      new HTTPException(401, {
        res: new Response(null, {
          headers: { "www-authenticate": "Bearer", "content-type": "text/plain" },
        }),
      }),
    ).request("/");
    expect(res.headers.get("www-authenticate")).toBe("Bearer");
    expect(res.headers.get("content-type")).toContain("application/json");
    expect(await res.json()).toEqual(errorBody("UNAUTHORIZED", "Bad request"));
  });

  it("turns anything else into 500 INTERNAL_ERROR and logs it with the request id", async () => {
    const error = vi.spyOn(console, "error").mockImplementation(() => {});
    const res = await appThrowing(new Error("boom")).request("/");
    expect(res.status).toBe(500);
    expect(await res.json()).toEqual(errorBody("INTERNAL_ERROR", "Internal error"));
    const logged = JSON.parse(error.mock.calls[0]![0] as string);
    expect(logged).toEqual({
      message: "unhandled error",
      requestId: res.headers.get("x-request-id"),
      error: "boom",
    });
    error.mockRestore();
  });

  it("treats a 5xx HTTPException as unexpected", async () => {
    const error = vi.spyOn(console, "error").mockImplementation(() => {});
    const res = await appThrowing(new HTTPException(502)).request("/");
    expect(res.status).toBe(500);
    error.mockRestore();
  });
});

describe("workerApp", () => {
  it("answers unknown routes with 404 NOT_FOUND and a request id", async () => {
    const res = await workerApp(new Hono()).request("/missing");
    expect(res.status).toBe(404);
    expect(res.headers.get("x-request-id")).toMatch(/^[0-9a-f-]{36}$/);
    expect(await res.json()).toEqual(errorBody("NOT_FOUND", "Not found"));
  });

  it("adds the request id to responses built outside Hono", async () => {
    const app = workerApp(new Hono());
    app.get("/raw", () => Response.json({ ok: true }));
    const res = await app.request("/raw");
    expect(res.headers.get("x-request-id")).toMatch(/^[0-9a-f-]{36}$/);
  });
});

describe("codeForStatus", () => {
  it("maps 5xx to INTERNAL_ERROR and unknown 4xx to BAD_REQUEST", () => {
    expect(codeForStatus(503)).toBe("INTERNAL_ERROR");
    expect(codeForStatus(418)).toBe("BAD_REQUEST");
  });
});

describe("normalizeAuthError", () => {
  it("wraps a Better Auth error and keeps its code and headers", async () => {
    const res = await normalizeAuthError(json(401, { code: "INVALID_TOKEN", message: "Bad" }));
    expect(res.status).toBe(401);
    expect(res.headers.get("set-cookie")).toBe("a=b");
    expect(await res.json()).toEqual(errorBody("INVALID_TOKEN", "Bad"));
  });

  it("derives the code and message from the status when the body has none", async () => {
    const res = await normalizeAuthError(
      new Response("{}", {
        status: 404,
        statusText: "Not Found",
        headers: { "content-type": "application/json" },
      }),
    );
    expect(await res.json()).toEqual(errorBody("NOT_FOUND", "Not Found"));
  });

  it("passes through successes, non-JSON bodies, uniform errors, and unparsable JSON", async () => {
    const ok = json(200, { ok: true });
    const text = new Response("nope", { status: 400 });
    const uniform = json(400, errorBody("BAD_REQUEST", "x"));
    const broken = new Response("{", {
      status: 400,
      headers: { "content-type": "application/json" },
    });
    expect(await normalizeAuthError(ok)).toBe(ok);
    expect(await normalizeAuthError(text)).toBe(text);
    expect(await normalizeAuthError(uniform)).toBe(uniform);
    expect(await normalizeAuthError(broken)).toBe(broken);
  });
});
