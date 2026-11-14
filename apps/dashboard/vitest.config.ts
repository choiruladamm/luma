import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";
import { backendVars } from "./backend-vars";

export default defineConfig(async () => {
  // The backend owns the schema: apply its migrations so changes that break the dashboard show up here.
  const migrations = await readD1Migrations("../backend/migrations");
  return {
    plugins: [
      cloudflareTest({
        wrangler: { configPath: "./wrangler.jsonc", environment: "dev" },
        miniflare: {
          // Every test request comes from the same IP: the real limits are raised.
          // 429 is tested by overriding the binding.
          ratelimits: {
            RATE_LIMITER: { namespace_id: "1101", simple: { limit: 10_000, period: 60 } },
            ADMIN_RATE_LIMITER: { namespace_id: "1102", simple: { limit: 10_000, period: 60 } },
          },
          bindings: {
            ...backendVars("dev"),
            TEST_MIGRATIONS: migrations,
            ADMIN_EMAILS: "admin@luma.test",
            // Keep the local .dev.vars (http://localhost) out: tests use the real https domain.
            BETTER_AUTH_URL: "https://luma-admin-dev.chrl.cloud",
            BETTER_AUTH_SECRET: "test-secret-dashboard-yang-lebih-dari-32-karakter",
            GOOGLE_CLIENT_SECRET: "test-google-secret",
            OPENROUTER_MANAGEMENT_KEY: "test-management-key",
          },
        },
      }),
    ],
    test: { setupFiles: ["./test/setup.ts"] },
  };
});
