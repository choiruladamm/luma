/**
 * Per-IP RATE_LIMITER binding limit in tests (vitest.config.ts). Higher than the
 * 60/minute in wrangler.jsonc: all test requests come from the same IP.
 */
export const TEST_RATE_LIMIT = 300;
