import { eq } from "drizzle-orm";
import type { OpenRouterAdmin } from "../../clients/openrouter";
import type { Db } from "../../db/client";
import { aiKeys, users } from "../../db/schema";
import { ApiError } from "../../lib/errors";
import { decryptText, encryptText } from "../../lib/crypto";

const DAY_MS = 24 * 60 * 60 * 1000;

/** Key diganti sehari sebelum kedaluwarsa, supaya device gak pegang key yang mati di tengah baca. */
export const ROTATE_BEFORE_MS = DAY_MS;

export type AiConfig = {
  dailyLimitUsd: number;
  ttlDays: number;
  workspaceId: string;
  encSecret: string;
  chatModels: string[];
  embeddingModels: string[];
};

const list = (value: string) =>
  value
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);

/** Angka dan model dari `vars` (docs/backend.md, Batas & pengaman). Model harus sama dengan guardrail OpenRouter. */
export const aiConfig = (env: Env): AiConfig => ({
  dailyLimitUsd: Number(env.AI_DAILY_LIMIT_USD),
  ttlDays: Number(env.AI_KEY_TTL_DAYS),
  workspaceId: env.OPENROUTER_WORKSPACE_ID,
  encSecret: env.AI_KEY_ENC_SECRET,
  chatModels: list(env.AI_CHAT_MODELS),
  embeddingModels: list(env.AI_EMBEDDING_MODELS),
});

export type IssuedKey = { key: string; expiresAt: string; dailyLimitUsd: number };

/**
 * Key subsidi user: dipakai ulang selama masih berlaku (dua device dapat key yang
 * sama, kuota gak dobel), dibuat lazy, diganti kalau hampir kedaluwarsa, gak
 * kebaca, atau diminta `rotate` (app dapat 401 dari OpenRouter).
 * Subrequest: 0 (pakai ulang), 1 (bikin / ubah limit), 2 (rotasi).
 */
export async function issueKey(
  db: Db,
  admin: OpenRouterAdmin,
  cfg: AiConfig,
  userId: string,
  { rotate = false, now = new Date() }: { rotate?: boolean; now?: Date } = {},
): Promise<IssuedKey> {
  // Satu query: status banned + key yang tersimpan.
  const [found] = await db
    .select({ banned: users.banned, key: aiKeys })
    .from(users)
    .leftJoin(aiKeys, eq(aiKeys.userId, users.id))
    .where(eq(users.id, userId));
  if (found?.banned) throw new ApiError(403, "AI_BANNED", "AI access is disabled for this account");

  const row = found?.key;
  const fresh = row && row.expiresAt.getTime() - now.getTime() > ROTATE_BEFORE_MS;
  if (row && fresh && !rotate) {
    const key = await decryptText(cfg.encSecret, row.keyEnc);
    if (key) {
      if (row.limitUsd !== cfg.dailyLimitUsd) {
        await admin.updateLimit(row.keyHash, cfg.dailyLimitUsd);
        await db.update(aiKeys).set({ limitUsd: cfg.dailyLimitUsd }).where(eq(aiKeys.userId, userId));
      }
      return { key, expiresAt: row.expiresAt.toISOString(), dailyLimitUsd: cfg.dailyLimitUsd };
    }
  }

  if (row) await admin.deleteKey(row.keyHash);
  const expiresAt = new Date(now.getTime() + cfg.ttlDays * DAY_MS);
  // shortcut: dua device minta bersamaan bisa bikin dua key; yang kalah jadi yatim
  // sampai kedaluwarsa (maks limit harian). Kunci per user kalau ini kejadian.
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
  await db
    .insert(aiKeys)
    .values({ userId, ...values })
    .onConflictDoUpdate({ target: aiKeys.userId, set: values });
  return { key: created.key, expiresAt: expiresAt.toISOString(), dailyLimitUsd: cfg.dailyLimitUsd };
}

export type AiUsage = {
  dailyLimitUsd: number;
  remainingUsd: number;
  usedTodayUsd: number;
  resetsAt: string;
};

/** Limit harian OpenRouter reset tengah malam UTC. */
export const nextUtcMidnight = (now: Date) =>
  new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1));

/** Sisa kuota hari ini. Belum punya key → kuota penuh, tanpa subrequest. */
export async function usage(
  db: Db,
  admin: OpenRouterAdmin,
  cfg: AiConfig,
  userId: string,
  now = new Date(),
): Promise<AiUsage> {
  const resetsAt = nextUtcMidnight(now).toISOString();
  const [row] = await db.select({ keyHash: aiKeys.keyHash }).from(aiKeys).where(eq(aiKeys.userId, userId));
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

/** Hapus key OpenRouter user (hapus akun). Baris D1 ikut terhapus lewat cascade users. */
export async function revokeKey(db: Db, admin: OpenRouterAdmin, userId: string) {
  const [row] = await db.select({ keyHash: aiKeys.keyHash }).from(aiKeys).where(eq(aiKeys.userId, userId));
  if (row) await admin.deleteKey(row.keyHash);
}
