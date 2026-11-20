import type { Context } from "hono";
import { HTTPException } from "hono/http-exception";
import type { ContentfulStatusCode } from "hono/utils/http-status";
import { log } from "./log";

/**
 * Codes every Worker can return; each Worker adds its own (docs/workers.md, Conventions).
 * UPPER_SNAKE_CASE, the same pattern as Better Auth's codes.
 */
export type BaseErrorCode =
  | "BAD_REQUEST"
  | "UNAUTHORIZED"
  | "FORBIDDEN"
  | "NOT_FOUND"
  | "PAYLOAD_TOO_LARGE"
  | "RATE_LIMITED"
  | "INTERNAL_ERROR";

/** Thrown anywhere in a request; `onError` turns it into `{error: {code, message}}`. */
export class ApiError<C extends string = BaseErrorCode> extends Error {
  constructor(
    readonly status: ContentfulStatusCode,
    readonly code: C,
    message: string,
    readonly headers: Record<string, string> = {},
  ) {
    super(message);
  }
}

export type ErrorBody<C extends string = string> = { error: { code: C; message: string } };

export const errorBody = <C extends string>(code: C, message: string): ErrorBody<C> => ({
  error: { code, message },
});

const CODES: Partial<Record<number, BaseErrorCode>> = {
  401: "UNAUTHORIZED",
  403: "FORBIDDEN",
  404: "NOT_FOUND",
  413: "PAYLOAD_TOO_LARGE",
  429: "RATE_LIMITED",
};

/** The base code for an HTTP status that carries no code of its own. */
export const codeForStatus = (status: number): BaseErrorCode =>
  status >= 500 ? "INTERNAL_ERROR" : (CODES[status] ?? "BAD_REQUEST");

/** `app.onError`: an ApiError as is, a 4xx HTTPException by status, anything else 500 + a log line. */
export const onError = (err: Error, c: Context) => {
  if (err instanceof ApiError) {
    for (const [k, v] of Object.entries(err.headers)) c.header(k, v);
    return c.json(errorBody(err.code, err.message), err.status);
  }
  if (err instanceof HTTPException && err.status < 500) {
    for (const [k, v] of err.res?.headers ?? []) {
      if (k !== "content-type" && k !== "content-length") c.header(k, v);
    }
    return c.json(errorBody(codeForStatus(err.status), err.message || "Bad request"), err.status);
  }
  log.error("unhandled error", { request_id: c.get("requestId"), error: err.message });
  return c.json(errorBody("INTERNAL_ERROR", "Internal error"), 500);
};

/** `app.notFound` and catch-all routes. */
export const notFound = (): never => {
  throw new ApiError(404, "NOT_FOUND", "Not found");
};

/**
 * Wraps a Better Auth `{code, message}` error in `{error: {code, message}}`, keeping Better
 * Auth's own code. Successes, non-JSON bodies, and bodies already in the format pass through.
 */
export async function normalizeAuthError(res: Response): Promise<Response> {
  if (res.ok || !res.headers.get("content-type")?.includes("application/json")) return res;
  const body = await res
    .clone()
    .json<{ code?: string; message?: string; error?: unknown } | null>()
    .catch(() => null);
  if (!body || body.error !== undefined) return res;
  const headers = new Headers(res.headers);
  headers.delete("content-length");
  return Response.json(
    errorBody(body.code ?? codeForStatus(res.status), body.message ?? res.statusText),
    { status: res.status, headers },
  );
}
