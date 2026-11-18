// Node-side (vite/vitest config): backend `vars` the dashboard reads, taken from the backend
// wrangler config of the same env so there is one source. Picked up on the next dashboard deploy.
import { unstable_readConfig } from "wrangler";

export const BACKEND_VARS = [
  "SYNC_ENABLED",
  "BACKUP_ENABLED",
  "AI_KEY_ENABLED",
  "OPENROUTER_WORKSPACE_ID",
  "AI_MONTHLY_BUDGET_USD",
] as const;

export type BackendVars = Record<(typeof BACKEND_VARS)[number], string>;

export function backendVars(env: string | undefined): BackendVars {
  if (env !== "dev" && env !== "prod" && env !== "e2e")
    throw new Error(`CLOUDFLARE_ENV must be dev, prod, or e2e, got ${env}`);
  // The local e2e env reads the backend's dev values.
  const { vars } = unstable_readConfig(
    { config: "../backend/wrangler.jsonc", env: env === "e2e" ? "dev" : env },
    { hideWarnings: true },
  );
  // oxlint-disable-next-line typescript/no-unsafe-type-assertion -- the map above checked every BACKEND_VARS name
  return Object.fromEntries(
    BACKEND_VARS.map((name) => {
      const value = vars[name];
      if (typeof value !== "string" || value === "")
        throw new Error(`backend ${env} var ${name} is missing`);
      return [name, value];
    }),
  ) as BackendVars;
}
