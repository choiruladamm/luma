// Tabel D1 (docs/backend.md, Schema D1). Property camelCase, kolom snake_case.
// Tabel Better Auth di auth-schema.ts (hasil `npx auth@latest generate`, jangan diedit manual).
import { integer, sqliteTable, text } from "drizzle-orm/sqlite-core";
import { users } from "./auth-schema";

export * from "./auth-schema";

/** Kode undangan beta: sekali pakai, dikonsumsi saat sign-up. */
export const inviteCodes = sqliteTable("invite_codes", {
  code: text("code").primaryKey(),
  usedBy: text("used_by").references(() => users.id, { onDelete: "set null" }),
  usedAt: integer("used_at", { mode: "timestamp_ms" }),
});
