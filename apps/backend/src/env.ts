import type { OpenRouterAdmin } from "./clients/openrouter";
import type { Db } from "./db/client";

export type SessionUser = { id: string; name: string; email: string; image: string | null };

export type AppEnv = {
  Bindings: Env;
  /** `db` + `openrouter` dari middleware `deps`, `user` dari `requireSession`. */
  Variables: { requestId: string; user: SessionUser; db: Db; openrouter: OpenRouterAdmin };
};

/** Saklar darurat di `vars` (docs/backend.md, Aturan server). */
export type FeatureFlag = "SYNC_ENABLED" | "BACKUP_ENABLED" | "AI_KEY_ENABLED";
