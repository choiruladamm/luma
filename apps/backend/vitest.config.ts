import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";
import { TEST_RATE_LIMIT } from "./test/helpers/limits";

export default defineConfig(async () => {
  const migrations = await readD1Migrations("../../packages/core/migrations");
  return {
    plugins: [
      cloudflareTest({
        wrangler: { configPath: "./wrangler.jsonc", environment: "dev" },
        miniflare: {
          // Raised per-IP limit: every test request comes from the same IP
          // ("unknown"), so the real 60/minute would 429 a large test file.
          // 429 behavior is tested through a binding override + the rate-limit test.
          ratelimits: {
            RATE_LIMITER: { namespace_id: "1001", simple: { limit: TEST_RATE_LIMIT, period: 60 } },
          },
          bindings: {
            TEST_MIGRATIONS: migrations,
            BETTER_AUTH_SECRET: "test-secret-yang-panjangnya-lebih-dari-32-karakter",
            GOOGLE_CLIENT_SECRET: "",
            OPENROUTER_MANAGEMENT_KEY: "test-management-key",
            // 32 zero bytes, base64; test only.
            AI_KEY_ENC_SECRET: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
          },
        },
      }),
    ],
    test: {
      setupFiles: ["./test/setup.ts"],
      coverage: {
        provider: "istanbul" as const,
        // @luma/core has no tests of its own: the backend's tests exercise it, so it is measured
        // here. @luma/worker-kit is measured by its own tests (make packages-test).
        allowExternal: true,
        include: ["src/**/*.ts", "../../packages/core/src/**/*.ts"],
        exclude: [
          "src/index.ts",
          "src/env.ts",
          "../../packages/core/src/db/schema.ts",
          "../../packages/core/src/db/auth-schema.ts",
          "../../packages/core/src/testing/**",
        ],
        thresholds: { statements: 100, branches: 93.05, functions: 100, lines: 100 },
      },
    },
  };
});
