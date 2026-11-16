import type { ErrorCode } from "../../worker/lib/errors";
import { id, type Messages } from "../i18n/id";

export type ClientErrorCode = ErrorCode | "NETWORK" | "ACCESS_EXPIRED";

/**
 * Error from the dashboard API. It carries the code, not copy: the worker's message is English
 * and internal, and the copy depends on the UI language at render time (`errorText`).
 */
export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: ClientErrorCode,
    readonly serverMessage?: string,
  ) {
    super(code);
  }
}

/** Copy to show for any error, in the current UI language (`t.errors`). */
export const errorText = (error: Error, t: Messages) => t.errors[error instanceof ApiError ? error.code : "INTERNAL_ERROR"];

/** Turn a failed response (`{"error": {"code", "message"}}`) into an ApiError. */
export async function toApiError(res: Response): Promise<ApiError> {
  const body = (await res.json().catch(() => null)) as { error?: { code?: string; message?: string } } | null;
  const code = body?.error?.code;
  // Our worker's 401 always has a JSON code; a bare 401 is Cloudflare Access saying its own session
  // expired (it answers so, instead of redirecting, because requests send X-Requested-With).
  if (res.status === 401 && code === undefined) return new ApiError(401, "ACCESS_EXPIRED");
  const known = code !== undefined && Object.hasOwn(id.errors, code) ? (code as ClientErrorCode) : "INTERNAL_ERROR";
  return new ApiError(res.status, known, body?.error?.message);
}

/** Return the JSON of an ok response, throw ApiError otherwise (network failures included). */
export async function unwrap<T>(request: Promise<{ ok: boolean; json(): Promise<T> }>): Promise<T> {
  let res: { ok: boolean; json(): Promise<T> };
  try {
    res = await request;
  } catch {
    throw new ApiError(0, "NETWORK");
  }
  if (!res.ok) throw await toApiError(res as unknown as Response);
  return res.json();
}

/** Like `unwrap` for responses without a body (204): resolves on ok, throws ApiError otherwise. */
export async function unwrapEmpty(request: Promise<{ ok: boolean }>): Promise<void> {
  let res: { ok: boolean };
  try {
    res = await request;
  } catch {
    throw new ApiError(0, "NETWORK");
  }
  if (!res.ok) throw await toApiError(res as unknown as Response);
}
