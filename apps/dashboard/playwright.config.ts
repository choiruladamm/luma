import { defineConfig, devices } from "@playwright/test";

// End-to-end: the real SPA + Worker through `vite dev` in the local e2e env (own D1 state,
// test secrets), driven by the installed Chrome. Run with `make dashboard-e2e`.
const PORT = 5174;

export default defineConfig({
  testDir: "./e2e",
  globalSetup: "./e2e/global-setup.ts",
  fullyParallel: false,
  workers: 1,
  retries: 0,
  reporter: [["list"]],
  use: {
    baseURL: `http://localhost:${PORT}`,
    channel: "chrome",
    // Specs assert the Indonesian copy; the UI follows the browser language (e2e/i18n.spec.ts).
    locale: "id-ID",
    storageState: "e2e/.auth/admin.json",
    trace: "retain-on-failure",
  },
  projects: [
    { name: "desktop", use: { viewport: { width: 1440, height: 900 } } },
    { name: "phone", use: { ...devices["Pixel 7"], channel: "chrome" }, grep: /@phone/ },
  ],
  webServer: {
    command: `CLOUDFLARE_ENV=e2e bunx vite dev --port ${PORT} --strictPort`,
    url: `http://localhost:${PORT}/login`,
    reuseExistingServer: false,
    timeout: 60_000,
  },
});
