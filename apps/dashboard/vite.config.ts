import { cloudflare } from "@cloudflare/vite-plugin";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";
import { backendVars } from "./backend-vars";

// The Cloudflare env (dev/prod in wrangler.jsonc) is picked by CLOUDFLARE_ENV at dev and build time.
export default defineConfig({
  plugins: [
    react(),
    cloudflare({
      // Same local state as `make backend-dev`: the dashboard's local D1 is the backend's.
      persistState: { path: "../backend/.wrangler/state" },
      config: (config) => ({ vars: { ...config.vars, ...backendVars(process.env.CLOUDFLARE_ENV) } }),
    }),
  ],
});
