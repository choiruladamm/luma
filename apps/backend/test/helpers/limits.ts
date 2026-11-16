/**
 * Limit binding RATE_LIMITER per IP di test (vitest.config.ts). Lebih gede dari
 * 60/menit di wrangler.jsonc: semua request test datang dari IP yang sama.
 */
export const TEST_RATE_LIMIT = 300;
