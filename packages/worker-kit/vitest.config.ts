import { defineConfig } from "vitest/config";

// The kit is plain Hono: its tests run on Node, no workerd needed.
export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
    coverage: {
      provider: "istanbul",
      include: ["src/**/*.ts"],
      // The testing helpers load only in workerd; the Workers' tests exercise them.
      exclude: ["src/testing/**"],
      thresholds: { statements: 100, branches: 100, functions: 100, lines: 100 },
    },
  },
});
