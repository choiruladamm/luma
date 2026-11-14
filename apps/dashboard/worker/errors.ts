import type { Context } from "hono";
import { HTTPException } from "hono/http-exception";
import type { ContentfulStatusCode } from "hono/utils/http-status";

/** Kode error dashboard (docs/dashboard.md, Endpoint); format sama dengan backend. */
export type ErrorCode =
  | "BAD_REQUEST"
  | "UNAUTHORIZED"
  | "FORBIDDEN"
  | "NOT_FOUND"
  | "RATE_LIMITED"
  | "OPENROUTER_FAILED"
  | "INTERNAL_ERROR";

export class ApiError extends Error {
  constructor(
    readonly status: ContentfulStatusCode,
    readonly code: ErrorCode,
    message: string,
    readonly headers: Record<string, string> = {},
  ) {
    super(message);
  }
}

const body = (code: ErrorCode, message: string) => ({ error: { code, message } });

/** `app.onError`: ApiError apa adanya, sisanya 500 + log JSON terstruktur. */
export const onError = (err: Error, c: Context) => {
  if (err instanceof ApiError) {
    for (const [k, v] of Object.entries(err.headers)) c.header(k, v);
    return c.json(body(err.code, err.message), err.status);
  }
  if (err instanceof HTTPException && err.status < 500) {
    return c.json(body("BAD_REQUEST", err.message || "Bad request"), err.status);
  }
  console.error(JSON.stringify({ message: "unhandled error", requestId: c.get("requestId"), error: err.message }));
  return c.json(body("INTERNAL_ERROR", "Internal error"), 500);
};
