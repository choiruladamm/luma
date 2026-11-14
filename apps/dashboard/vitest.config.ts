import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

export default defineConfig(async () => {
  // Schema milik backend: migrasinya yang diterapkan, jadi perubahan yang merusak dashboard ketahuan di sini.
  const migrations = await readD1Migrations("../backend/migrations");
  return {
    plugins: [
      cloudflareTest({
        wrangler: { configPath: "./wrangler.jsonc", environment: "dev" },
        miniflare: {
          // Semua request test datang dari IP yang sama: limit asli (60/menit) dinaikin.
          // 429 dites lewat override binding.
          ratelimits: {
            RATE_LIMITER: { namespace_id: "1101", simple: { limit: 10_000, period: 60 } },
            ADMIN_RATE_LIMITER: { namespace_id: "1102", simple: { limit: 10_000, period: 60 } },
          },
          bindings: {
            TEST_MIGRATIONS: migrations,
            ADMIN_EMAILS: "admin@luma.test",
            // .dev.vars lokal (http://localhost) gak boleh ikut: test pakai domain https asli.
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
