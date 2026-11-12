import { Hono } from "hono";
import { getAuth } from "../../auth/auth";
import type { AppEnv } from "../../env";
import { type ErrorCode, errorBody } from "../../lib/errors";
import { limitBody } from "../../middleware/body-limit";

/** Body auth kecil (email, password, idToken). */
const AUTH_BODY_LIMIT = 16 * 1024;

const codeForStatus = (status: number): ErrorCode => {
  if (status === 401) return "UNAUTHORIZED";
  if (status === 404) return "NOT_FOUND";
  if (status === 413) return "PAYLOAD_TOO_LARGE";
  if (status === 429) return "RATE_LIMITED";
  if (status >= 500) return "INTERNAL_ERROR";
  return "BAD_REQUEST";
};

/**
 * Error Better Auth `{code, message}` dibungkus jadi format seragam
 * `{error: {code, message}}`; kode Better Auth (UPPER_SNAKE) dipertahankan.
 */
export async function normalizeAuthError(res: Response): Promise<Response> {
  if (res.ok || !res.headers.get("content-type")?.includes("application/json")) return res;
  const body = (await res.clone().json().catch(() => null)) as {
    code?: string;
    message?: string;
    error?: unknown;
  } | null;
  if (!body || body.error !== undefined) return res;
  const headers = new Headers(res.headers);
  headers.delete("content-length");
  return Response.json(
    errorBody((body.code as ErrorCode) ?? codeForStatus(res.status), body.message ?? res.statusText),
    { status: res.status, headers },
  );
}

export const auth = new Hono<AppEnv>()
  .use(limitBody(AUTH_BODY_LIMIT))
  .on(["GET", "POST"], "/*", async (c) =>
    normalizeAuthError(await getAuth(c.env).handler(c.req.raw)),
  );
