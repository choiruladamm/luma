// The backend's values for the worker kit's middleware.

/** Period of the RATE_LIMITER binding (wrangler.jsonc). */
export const RATE_LIMIT_PERIOD_SECONDS = 60;

/** Default JSON body limit (sync push max 1MB). File uploads have their own limit. */
export const JSON_BODY_LIMIT = 1024 * 1024;

/** Retry-After when a feature is off: the client stops until the next trigger after this delay. */
export const DISABLED_RETRY_AFTER_SECONDS = 3600;
