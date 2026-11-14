import type { Context } from "hono";
import { HTTPException } from "hono/http-exception";
import type { ContentfulStatusCode } from "hono/utils/http-status";

/** Dashboard error codes (docs/dashboard.md, Endpoint); same format as the backend. */
export type ErrorCode =
  | "BAD_REQUEST"
  | "UNAUTHORIZED"
  | "FORBIDDEN"
  | "NOT_FOUND"
  | "INVITE_CODE_USED"
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

/** `app.onError`: ApiError as is, anything else → 500 + structured JSON log. */
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
