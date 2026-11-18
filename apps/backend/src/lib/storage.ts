// Per-user R2 storage rules, used by book files, backups, and account deletion
// (docs/backend.md, Files and cloud backups). Pure: no D1, no bindings.
import { ApiError } from "./errors";

/** The R2 prefix owned by one user. */
export const userPrefix = (userId: string) => `u/${userId}/`;

/** The Workers free body limit; a single file or snapshot must not exceed it. */
export const MAX_UPLOAD_BYTES = 100 * 1024 * 1024;

/** `Content-Length` is required (R2 needs an exact length, the quota is checked before upload). */
export function uploadSize(header: string | undefined): number {
  const size = Number(header);
  if (!header || !Number.isSafeInteger(size) || size < 0) {
    throw new ApiError(400, "BAD_REQUEST", "Content-Length required");
  }
  if (size > MAX_UPLOAD_BYTES) {
    throw new ApiError(413, "PAYLOAD_TOO_LARGE", `Body exceeds ${MAX_UPLOAD_BYTES} bytes`);
  }
  return size;
}

/**
 * The request body is guaranteed to be exactly `size` long: R2 needs an exact length, and a
 * client that lies about `Content-Length` makes the upload fail instead of slipping past the quota.
 */
export const fixedLength = (body: ReadableStream | null, size: number) =>
  (body ?? new Response("").body!).pipeThrough(new FixedLengthStream(size));
