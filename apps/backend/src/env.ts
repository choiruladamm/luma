import type { OpenRouterAdmin } from "@luma/core/openrouter";
import type { Db } from "@luma/core/db/client";
import type { SessionUser } from "@luma/contracts/backend/account";

/** The API version a request came in on: the mount's prefix (docs/backend.md, API versions). */
export type Wire = "v1" | "v2";

export type AppEnv = {
  Bindings: Env;
  /**
   * `db` + `openrouter` from the `deps` middleware, `user` from `requireSession`, `wire` from the
   * mount. `wireDone`: the route already built its body for `wire` (sync pull), so the v1 adapter
   * leaves it alone.
   */
  Variables: {
    requestId: string;
    user: SessionUser;
    db: Db;
    openrouter: OpenRouterAdmin;
    wire: Wire;
    wireDone?: true;
  };
};

/** Kill switches in `vars` (docs/backend.md, Request pipeline and API conventions). */
export type FeatureFlag = "SYNC_ENABLED" | "BACKUP_ENABLED" | "AI_KEY_ENABLED";
