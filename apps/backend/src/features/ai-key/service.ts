import type { OpenRouterAdmin } from "../../clients/openrouter";
import type { Db } from "../../db/client";
import { decryptText, encryptText } from "../../lib/crypto";
import { csv, DAY_MS } from "../../lib/encoding";
import { ApiError } from "../../lib/errors";
import { findKeyHash, findUserKey, saveKey, setKeyLimit } from "./repo";

/** The key is replaced a day before it expires, so a device never holds a dead key mid-read. */
export const ROTATE_BEFORE_MS = DAY_MS;

export type AiConfig = {
  dailyLimitUsd: number;
  ttlDays: number;
  workspaceId: string;
  encSecret: string;
  chatModels: string[];
  embeddingModels: string[];
};

/** Numbers and models from `vars` (docs/backend.md, AI subsidy). Models must match the OpenRouter guardrail. */
export const aiConfig = (env: Env): AiConfig => ({
  dailyLimitUsd: Number(env.AI_DAILY_LIMIT_USD),
  ttlDays: Number(env.AI_KEY_TTL_DAYS),
  workspaceId: env.OPENROUTER_WORKSPACE_ID,
  encSecret: env.AI_KEY_ENC_SECRET,
  chatModels: csv(env.AI_CHAT_MODELS),
  embeddingModels: csv(env.AI_EMBEDDING_MODELS),
});

/** The user's key + banned status; banned → 403 `AI_BANNED` (meter "Dicabut", board Kuota AI 01). */
async function allowedKey(db: Db, userId: string) {
  const found = await findUserKey(db, userId);
  if (found.banned) throw new ApiError(403, "AI_BANNED", "AI access is disabled for this account");
  return found.key;
}

export type IssuedKey = { key: string; expiresAt: string; dailyLimitUsd: number };

/**
 * The user's subsidized key: reused while still valid (two devices get the same key,
 * so quota isn't doubled), created lazily, replaced when close to expiry, unreadable,
 * or `rotate` is requested and the key is already gone from OpenRouter.
 * `rotate` for a key that still exists is ignored: the daily limit is attached to the
 * key, so free rotation would mean a fresh daily quota on every request.
 * Subrequests: 0 (reuse), 1 (create / change limit / check `rotate`), 2–3 (rotation).
 */
export async function issueKey(
  db: Db,
  admin: OpenRouterAdmin,
  cfg: AiConfig,
  userId: string,
  { rotate = false, now = new Date() }: { rotate?: boolean; now?: Date } = {},
): Promise<IssuedKey> {
  const row = await allowedKey(db, userId);
  const fresh = row && row.expiresAt.getTime() - now.getTime() > ROTATE_BEFORE_MS;
  if (row && fresh) {
    const key = await decryptText(cfg.encSecret, row.keyEnc);
    if (key && (!rotate || (await admin.keyExists(row.keyHash)))) {
      if (row.limitUsd !== cfg.dailyLimitUsd) {
        await admin.updateLimit(row.keyHash, cfg.dailyLimitUsd);
        await setKeyLimit(db, userId, cfg.dailyLimitUsd);
      }
      return { key, expiresAt: row.expiresAt.toISOString(), dailyLimitUsd: cfg.dailyLimitUsd };
    }
  }

  if (row) await admin.deleteKey(row.keyHash);
  const expiresAt = new Date(now.getTime() + cfg.ttlDays * DAY_MS);
  // ponytail: two devices asking at once can create two keys; the loser is orphaned
  // until it expires (at most the daily limit). Lock per user if this ever happens.
  const created = await admin.createKey({
    name: `luma-${userId}`,
    limitUsd: cfg.dailyLimitUsd,
    expiresAt,
    workspaceId: cfg.workspaceId,
  });
  const values = {
    keyHash: created.hash,
    keyEnc: await encryptText(cfg.encSecret, created.key),
    limitUsd: cfg.dailyLimitUsd,
    expiresAt,
    createdAt: now,
  };
  await saveKey(db, userId, values);
  return { key: created.key, expiresAt: expiresAt.toISOString(), dailyLimitUsd: cfg.dailyLimitUsd };
}

export type AiUsage = {
  dailyLimitUsd: number;
  remainingUsd: number;
  usedTodayUsd: number;
  resetsAt: string;
};

/** The OpenRouter daily limit resets at midnight UTC. */
export const nextUtcMidnight = (now: Date) =>
  new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1));

/** Quota left today. No key yet → full quota, no subrequest. */
export async function usage(
  db: Db,
  admin: OpenRouterAdmin,
  cfg: AiConfig,
  userId: string,
  now = new Date(),
): Promise<AiUsage> {
  const resetsAt = nextUtcMidnight(now).toISOString();
  const row = await allowedKey(db, userId);
  if (!row) {
    return { dailyLimitUsd: cfg.dailyLimitUsd, remainingUsd: cfg.dailyLimitUsd, usedTodayUsd: 0, resetsAt };
  }
  const key = await admin.getUsage(row.keyHash);
  const limit = key.limit ?? cfg.dailyLimitUsd;
  return {
    dailyLimitUsd: limit,
    remainingUsd: key.limitRemaining ?? Math.max(0, limit - key.usageDaily),
    usedTodayUsd: key.usageDaily,
    resetsAt,
  };
}

/** Deletes the user's OpenRouter key (account deletion). The D1 row goes with the users cascade. */
export async function revokeKey(db: Db, admin: OpenRouterAdmin, userId: string) {
  const keyHash = await findKeyHash(db, userId);
  if (keyHash) await admin.deleteKey(keyHash);
}
