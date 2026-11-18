import type { Context } from "hono";
import { HTTPException } from "hono/http-exception";
import type { ContentfulStatusCode } from "hono/utils/http-status";

/** UPPER_SNAKE_CASE error codes, the same pattern as Better Auth (docs/backend.md, Request pipeline and API conventions). */
export type ErrorCode =
  | "BAD_REQUEST"
  | "UNAUTHORIZED"
  | "NOT_FOUND"
  | "PAYLOAD_TOO_LARGE"
  | "RATE_LIMITED"
  | "SERVICE_DISABLED"
  | "AI_BANNED"
  | "STORAGE_FULL"
  | "QUOTA_EXCEEDED"
  | "BACKUP_NOT_FOUND"
  | "INTERNAL_ERROR";

export type ErrorBody = { error: { code: ErrorCode; message: string } };

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

export const errorBody = (code: ErrorCode, message: string): ErrorBody => ({
  error: { code, message },
});

export const errorResponse = (c: Context, e: ApiError) => {
  for (const [k, v] of Object.entries(e.headers)) c.header(k, v);
  return c.json(errorBody(e.code, e.message), e.status);
};

/** `app.onError`: an ApiError as-is, anything else becomes 500 + a structured JSON log. */
export const onError = (err: Error, c: Context) => {
  if (err instanceof ApiError) return errorResponse(c, err);
  if (err instanceof HTTPException && err.status < 500) {
    return c.json(errorBody("BAD_REQUEST", err.message || "Bad request"), err.status);
  }
  console.error(
    JSON.stringify({
      message: "unhandled error",
      requestId: c.get("requestId"),
      error: err.message,
    }),
  );
  return c.json(errorBody("INTERNAL_ERROR", "Internal error"), 500);
};
