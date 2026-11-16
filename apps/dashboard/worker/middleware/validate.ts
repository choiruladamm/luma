import { zValidator } from "@hono/zod-validator";
import type { ValidationTargets } from "hono";
import type { ZodType } from "zod";
import { ApiError } from "../lib/errors";

/** zod validator with the dashboard error format (400 BAD_REQUEST). */
export const validate = <T extends keyof ValidationTargets, S extends ZodType>(target: T, schema: S) =>
  zValidator(target, schema, (result) => {
    if (!result.success) throw new ApiError(400, "BAD_REQUEST", result.error.issues[0]?.message ?? "Invalid input");
  });
