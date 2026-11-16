import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";
import { TEST_RATE_LIMIT } from "./test/helpers/limits";

export default defineConfig(async () => {
  const migrations = await readD1Migrations("./migrations");
  return {
    plugins: [
      cloudflareTest({
        wrangler: { configPath: "./wrangler.jsonc", environment: "dev" },
        miniflare: {
          // Limit per IP dinaikin: semua request test datang dari IP yang sama
          // ("unknown"), jadi 60/menit asli bikin file test gede kena 429.
          // Perilaku 429 dites lewat override binding + test rate-limit.
          ratelimits: { RATE_LIMITER: { namespace_id: "1001", simple: { limit: TEST_RATE_LIMIT, period: 60 } } },
          bindings: {
            TEST_MIGRATIONS: migrations,
            BETTER_AUTH_SECRET: "test-secret-yang-panjangnya-lebih-dari-32-karakter",
            GOOGLE_CLIENT_SECRET: "",
            OPENROUTER_MANAGEMENT_KEY: "test-management-key",
            // 32 byte nol, base64: cuma buat test
            AI_KEY_ENC_SECRET: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
          },
        },
      }),
    ],
    test: {
      setupFiles: ["./test/setup.ts"],
      coverage: {
        provider: "istanbul" as const,
        include: ["src/**/*.ts"],
        exclude: ["src/index.ts", "src/env.ts", "src/db/schema.ts", "src/db/auth-schema.ts"],
        thresholds: { lines: 80, functions: 80, branches: 80, statements: 80 },
      },
    },
  };
});
