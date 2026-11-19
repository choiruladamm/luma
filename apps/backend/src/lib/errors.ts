import { type BaseErrorCode, ApiError as KitApiError } from "@luma/worker-kit/errors";

/** Backend error codes: the shared ones plus the backend's own (docs/backend.md, Request pipeline and API conventions). */
export type ErrorCode =
  | BaseErrorCode
  | "SERVICE_DISABLED"
  | "AI_BANNED"
  | "STORAGE_FULL"
  | "QUOTA_EXCEEDED"
  | "BACKUP_NOT_FOUND";

/** An error the backend throws with one of its own codes. */
export class ApiError extends KitApiError<ErrorCode> {}
