import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

// The SPA's own tests (happy-dom, MSW in node). The worker tests run in workerd: vitest.config.ts.
export default defineConfig({
  plugins: [react()],
  test: {
    name: "client",
    environment: "happy-dom",
    environmentOptions: { happyDOM: { url: "http://localhost/" } },
    include: ["test/client/**/*.test.{ts,tsx}"],
    setupFiles: ["./test/client/setup.ts"],
  },
});
