import { env } from "cloudflare:test";
import { eq } from "drizzle-orm";
import { describe, expect, it, vi } from "vitest";
import type { KeyUsage, OpenRouterAdmin } from "../../src/clients/openrouter";
import { createDb } from "../../src/db/client";
import { aiKeys, users } from "../../src/db/schema";
import {
  aiConfig,
  issueKey,
  nextUtcMidnight,
  ROTATE_BEFORE_MS,
  revokeKey,
  usage,
} from "../../src/features/ai-key/service";
import { ApiError } from "../../src/lib/errors";
import { signUp } from "../helpers/auth";

const DAY = 24 * 60 * 60 * 1000;
const cfg = aiConfig(env);

function fakeAdmin() {
  let n = 0;
  const admin = {
    createKey: vi.fn(async () => ({ key: `sk-${++n}`, hash: `h-${n}` })),
    updateLimit: vi.fn(async () => {}),
    getUsage: vi.fn(async (): Promise<KeyUsage> => ({ limit: 0.02, limitRemaining: 0.015, usageDaily: 0.005 })),
    deleteKey: vi.fn(async () => {}),
  } satisfies OpenRouterAdmin;
  return admin;
}

describe("aiConfig", () => {
  it("parses limits and model lists from vars", () => {
    expect(cfg.dailyLimitUsd).toBe(0.02);
    expect(cfg.ttlDays).toBe(30);
    expect(cfg.chatModels).toContain("deepseek/deepseek-v4.1-flash");
    expect(cfg.embeddingModels).toEqual(["qwen/qwen3-embedding-8b", "openai/text-embedding-3-large"]);
  });
});

describe("issueKey", () => {
  it("creates lazily, then reuses the same key with no OpenRouter call", async () => {
    const { userId } = await signUp();
    const db = createDb(env.DB);
    const admin = fakeAdmin();
    const now = new Date();

    const first = await issueKey(db, admin, cfg, userId, { now });
    expect(first.key).toBe("sk-1");
    expect(first.expiresAt).toBe(new Date(now.getTime() + 30 * DAY).toISOString());
    expect(admin.createKey).toHaveBeenCalledWith(
      expect.objectContaining({ limitUsd: 0.02, workspaceId: cfg.workspaceId }),
    );

    const again = await issueKey(db, admin, cfg, userId, { now });
    expect(again.key).toBe("sk-1");
    expect(admin.createKey).toHaveBeenCalledTimes(1);

    const [row] = await db.select().from(aiKeys).where(eq(aiKeys.userId, userId));
    expect(row?.keyEnc).not.toContain("sk-1");
  });

  it("rotates on request: deletes the old key and stores the new one", async () => {
    const { userId } = await signUp();
    const db = createDb(env.DB);
    const admin = fakeAdmin();
    await issueKey(db, admin, cfg, userId);

    const rotated = await issueKey(db, admin, cfg, userId, { rotate: true });

    expect(rotated.key).toBe("sk-2");
    expect(admin.deleteKey).toHaveBeenCalledWith("h-1");
    expect((await issueKey(db, admin, cfg, userId)).key).toBe("sk-2");
  });

  it("rotates a key that is about to expire", async () => {
    const { userId } = await signUp();
    const db = createDb(env.DB);
    const admin = fakeAdmin();
    const start = new Date();
    await issueKey(db, admin, cfg, userId, { now: start });

    const nearEnd = new Date(start.getTime() + 30 * DAY - ROTATE_BEFORE_MS + 1);
    expect((await issueKey(db, admin, cfg, userId, { now: nearEnd })).key).toBe("sk-2");
  });

  it("rotates when the stored key can no longer be decrypted", async () => {
    const { userId } = await signUp();
    const db = createDb(env.DB);
    const admin = fakeAdmin();
    await issueKey(db, admin, cfg, userId);
    const otherSecret = btoa(String.fromCharCode(...new Uint8Array(32).fill(1)));

    const issued = await issueKey(db, admin, { ...cfg, encSecret: otherSecret }, userId);

    expect(issued.key).toBe("sk-2");
    expect(admin.deleteKey).toHaveBeenCalledWith("h-1");
  });

  it("pushes a changed daily limit to the existing key", async () => {
    const { userId } = await signUp();
    const db = createDb(env.DB);
    const admin = fakeAdmin();
    await issueKey(db, admin, cfg, userId);

    const issued = await issueKey(db, admin, { ...cfg, dailyLimitUsd: 0.3 }, userId);

    expect(issued).toMatchObject({ key: "sk-1", dailyLimitUsd: 0.3 });
    expect(admin.updateLimit).toHaveBeenCalledWith("h-1", 0.3);
    const [row] = await db.select().from(aiKeys).where(eq(aiKeys.userId, userId));
    expect(row?.limitUsd).toBe(0.3);
  });

  it("refuses banned users without touching OpenRouter", async () => {
    const { userId } = await signUp();
    const db = createDb(env.DB);
    await db.update(users).set({ banned: true }).where(eq(users.id, userId));
    const admin = fakeAdmin();

    await expect(issueKey(db, admin, cfg, userId)).rejects.toMatchObject({
      status: 403,
      code: "AI_BANNED",
    } satisfies Partial<ApiError>);
    expect(admin.createKey).not.toHaveBeenCalled();
  });
});

describe("usage", () => {
  it("reports a full allowance without calling OpenRouter when no key exists", async () => {
    const { userId } = await signUp();
    const admin = fakeAdmin();
    const now = new Date("2026-11-12T15:00:00Z");

    expect(await usage(createDb(env.DB), admin, cfg, userId, now)).toEqual({
      dailyLimitUsd: 0.02,
      remainingUsd: 0.02,
      usedTodayUsd: 0,
      resetsAt: "2026-11-13T00:00:00.000Z",
    });
    expect(admin.getUsage).not.toHaveBeenCalled();
  });

  it("reads remaining quota from the key", async () => {
    const { userId } = await signUp();
    const db = createDb(env.DB);
    const admin = fakeAdmin();
    await issueKey(db, admin, cfg, userId);

    expect(await usage(db, admin, cfg, userId)).toMatchObject({ remainingUsd: 0.015, usedTodayUsd: 0.005 });
  });

  it("falls back to limit - usage when OpenRouter omits limit_remaining", async () => {
    const { userId } = await signUp();
    const db = createDb(env.DB);
    const admin = fakeAdmin();
    admin.getUsage.mockResolvedValueOnce({ limit: null, limitRemaining: null, usageDaily: 0.03 });
    await issueKey(db, admin, cfg, userId);

    expect(await usage(db, admin, cfg, userId)).toMatchObject({ dailyLimitUsd: 0.02, remainingUsd: 0 });
  });

  it("nextUtcMidnight rolls over months", () => {
    expect(nextUtcMidnight(new Date("2026-11-30T23:59:00Z")).toISOString()).toBe("2026-12-01T00:00:00.000Z");
  });
});

describe("revokeKey", () => {
  it("deletes the OpenRouter key only when the user has one", async () => {
    const { userId } = await signUp();
    const db = createDb(env.DB);
    const admin = fakeAdmin();
    await revokeKey(db, admin, userId);
    expect(admin.deleteKey).not.toHaveBeenCalled();

    await issueKey(db, admin, cfg, userId);
    await revokeKey(db, admin, userId);
    expect(admin.deleteKey).toHaveBeenCalledWith("h-1");
  });
});
