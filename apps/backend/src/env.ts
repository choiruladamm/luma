export type SessionUser = { id: string; name: string; email: string; image: string | null };

export type AppEnv = {
  Bindings: Env;
  Variables: { requestId: string; user: SessionUser };
};

/** Saklar darurat di `vars` (docs/backend.md, Aturan server). */
export type FeatureFlag = "SYNC_ENABLED" | "BACKUP_ENABLED" | "AI_KEY_ENABLED";
