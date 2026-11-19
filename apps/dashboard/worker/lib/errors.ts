import { type BaseErrorCode, ApiError as KitApiError } from "@luma/worker-kit/errors";

/** Dashboard error codes: the shared ones plus the dashboard's own (docs/dashboard.md, API routes and errors). */
export type ErrorCode = BaseErrorCode | "INVITE_CODE_USED" | "OPENROUTER_FAILED";

/** An error the dashboard throws with one of its own codes. */
export class ApiError extends KitApiError<ErrorCode> {}
