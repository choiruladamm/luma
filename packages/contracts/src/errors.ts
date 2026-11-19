import { z } from "zod";

/** Every error response of every Worker: `{error: {code, message}}` (docs/workers.md, Conventions). */
export const errorBodySchema = z.strictObject({
  error: z.strictObject({ code: z.string(), message: z.string() }),
});

/** Codes every Worker can return (the kit's `BaseErrorCode`; each app's `lib/errors.ts` checks it is covered). */
const baseCodes = [
  "BAD_REQUEST",
  "UNAUTHORIZED",
  "FORBIDDEN",
  "NOT_FOUND",
  "PAYLOAD_TOO_LARGE",
  "RATE_LIMITED",
  "INTERNAL_ERROR",
] as const;

/**
 * The backend's own codes: what its code throws, plus the invite codes its Better Auth hooks
 * reject sign-ups with.
 */
export const backendErrorCode = z.enum([
  ...baseCodes,
  "SERVICE_DISABLED",
  "AI_BANNED",
  "STORAGE_FULL",
  "QUOTA_EXCEEDED",
  "BACKUP_NOT_FOUND",
  "INVALID_INVITE_CODE",
  "INVITE_CODE_REQUIRED",
  "INVITE_CODE_USED",
]);

/**
 * A code Better Auth returns from `/v1/auth/*` (`INVALID_EMAIL_OR_PASSWORD`, `PASSWORD_TOO_SHORT`,
 * …). Better Auth owns that list and grows it, so only the shape is fixed; clients treat a code
 * they don't know as a generic failure.
 */
export const betterAuthErrorCode = z.string().regex(/^[A-Z][A-Z0-9_]*$/);

/** Every code on the backend's wire: its own or one Better Auth passed through. */
export const backendWireErrorCode = z.union([backendErrorCode, betterAuthErrorCode]);

/** Every code the dashboard can return. */
export const dashboardErrorCode = z.enum([...baseCodes, "INVITE_CODE_USED", "OPENROUTER_FAILED"]);
