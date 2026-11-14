// Backend vars injected at build/test time by backend-vars.ts (not in this app's wrangler.jsonc).
interface BackendVarsEnv {
  SYNC_ENABLED: string;
  BACKUP_ENABLED: string;
  AI_KEY_ENABLED: string;
  OPENROUTER_WORKSPACE_ID: string;
  AI_MONTHLY_BUDGET_USD: string;
}
interface Env extends BackendVarsEnv {}
declare namespace Cloudflare {
  interface Env extends BackendVarsEnv {}
}
