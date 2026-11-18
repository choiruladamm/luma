import type { OpenRouterAdmin } from "./clients/openrouter";
import type { Db } from "./db/client";

export type SessionUser = { id: string; name: string; email: string; image: string | null };

export type AppEnv = {
  Bindings: Env;
  /** `db` + `openrouter` from the `deps` middleware, `user` from `requireSession`. */
  Variables: { requestId: string; user: SessionUser; db: Db; openrouter: OpenRouterAdmin };
};

/** Kill switches in `vars` (docs/backend.md, Request pipeline and API conventions). */
export type FeatureFlag = "SYNC_ENABLED" | "BACKUP_ENABLED" | "AI_KEY_ENABLED";
