import type { dashboardErrorCode } from "@luma/contracts/errors";
import { type BaseErrorCode, ApiError as KitApiError } from "@luma/worker-kit/errors";
import type { z } from "zod";

/** Dashboard error codes, from the contract (docs/dashboard.md, API routes and errors). */
export type ErrorCode = z.infer<typeof dashboardErrorCode>;

/** Compile error when the kit adds a base code the contract's list lacks. */
type Covered<S extends ErrorCode> = S;
export type BaseCodesCovered = Covered<BaseErrorCode>;

/** An error the dashboard throws with one of its own codes. */
export class ApiError extends KitApiError<ErrorCode> {}
