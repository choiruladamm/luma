import type { backendErrorCode } from "@luma/contracts/errors";
import { type BaseErrorCode, ApiError as KitApiError } from "@luma/worker-kit/errors";
import type { z } from "zod";

/** Backend error codes, from the contract (docs/backend.md, Request pipeline and API conventions). */
export type ErrorCode = z.infer<typeof backendErrorCode>;

/** Compile error when the kit adds a base code the contract's list lacks. */
type Covered<S extends ErrorCode> = S;
export type BaseCodesCovered = Covered<BaseErrorCode>;

/** An error the backend throws with one of its own codes. */
export class ApiError extends KitApiError<ErrorCode> {}
