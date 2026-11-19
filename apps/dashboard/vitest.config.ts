import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";
import { backendVars } from "./backend-vars.ts";

export default defineConfig(async () => {
  // The schema lives in @luma/core: apply its migrations so a change that breaks the dashboard shows up.
  const migrations = await readD1Migrations("../../packages/core/migrations");
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
    test: {
      include: ["test/{unit,integration,golden}/**/*.test.ts"],
      setupFiles: ["./test/setup.ts"],
      coverage: {
        provider: "istanbul" as const,
        include: ["worker/**/*.ts"],
        exclude: ["worker/backend-env.d.ts"],
        thresholds: { statements: 99.27, branches: 92.12, functions: 100, lines: 99.19 },
      },
    },
  };
});
