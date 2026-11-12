// Tabel D1 (docs/backend.md, Schema D1). Property camelCase, kolom snake_case.
// Tabel Better Auth di auth-schema.ts (hasil `npx auth@latest generate`, jangan diedit manual).
import { integer, real, sqliteTable, text } from "drizzle-orm/sqlite-core";
import { users } from "./auth-schema";

export * from "./auth-schema";

/**
 * Key OpenRouter subsidi, satu per user (docs/backend.md, AI). Teks key cuma
 * dikasih OpenRouter sekali, jadi disimpan terenkripsi buat device kedua.
 */
export const aiKeys = sqliteTable("ai_keys", {
  userId: text("user_id")
    .primaryKey()
    .references(() => users.id, { onDelete: "cascade" }),
  keyHash: text("key_hash").notNull(),
  keyEnc: text("key_enc").notNull(),
  limitUsd: real("limit_usd").notNull(),
  expiresAt: integer("expires_at", { mode: "timestamp_ms" }).notNull(),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
});

/** Kode undangan beta: sekali pakai, dikonsumsi saat sign-up. */
export const inviteCodes = sqliteTable("invite_codes", {
  code: text("code").primaryKey(),
  usedBy: text("used_by").references(() => users.id, { onDelete: "set null" }),
  usedAt: integer("used_at", { mode: "timestamp_ms" }),
});
