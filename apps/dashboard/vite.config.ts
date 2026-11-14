import { cloudflare } from "@cloudflare/vite-plugin";
import { defineConfig } from "vite";

// Env Cloudflare (dev/prod di wrangler.jsonc) dipilih lewat CLOUDFLARE_ENV saat dev dan build.
export default defineConfig({
  plugins: [
    cloudflare({
      // State lokal yang sama dengan `make backend-dev`: D1 lokal dashboard = D1 lokal backend.
      persistState: { path: "../backend/.wrangler/state" },
    }),
  ],
});
