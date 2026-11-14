import { cloudflare } from "@cloudflare/vite-plugin";
import { defineConfig } from "vite";

// The Cloudflare env (dev/prod in wrangler.jsonc) is picked by CLOUDFLARE_ENV at dev and build time.
export default defineConfig({
  plugins: [
    cloudflare({
      // Same local state as `make backend-dev`: the dashboard's local D1 is the backend's.
      persistState: { path: "../backend/.wrangler/state" },
    }),
  ],
});
