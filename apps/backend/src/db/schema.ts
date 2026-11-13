// Tabel D1 (docs/backend.md, Schema D1). Property camelCase, kolom snake_case.
// Tabel Better Auth di auth-schema.ts (hasil `npx auth@latest generate`, jangan diedit manual).
import { index, integer, primaryKey, real, sqliteTable, text } from "drizzle-orm/sqlite-core";
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

/**
 * Pemakaian per user (docs/backend.md, Batas & pengaman): `bytes` = R2, dicek
 * terhadap `USER_STORAGE_BYTES` tiap upload. `seq` = urutan sync (#109).
 * `syncBytes` = ukuran record sync di D1 (panjang key + JSON data), dicek
 * terhadap `SYNC_STORAGE_BYTES`. `syncRows` = baris sync ditulis di hari UTC
 * `syncDay` (hari sejak epoch), dicek terhadap `SYNC_DAILY_WRITES`.
 */
export const userStorage = sqliteTable("user_storage", {
  userId: text("user_id")
    .primaryKey()
    .references(() => users.id, { onDelete: "cascade" }),
  bytes: integer("bytes").notNull().default(0),
  seq: integer("seq").notNull().default(0),
  syncBytes: integer("sync_bytes").notNull().default(0),
  syncDay: integer("sync_day").notNull().default(0),
  syncRows: integer("sync_rows").notNull().default(0),
});

/**
 * Data sync per baris (docs/backend.md, Sync antar device). `data` = JSON field
 * Dart (camelCase), null untuk tombstone. `seq` = urutan per user buat pull.
 * `schema_version` = versi schema Drift app pengirim; versi lebih lama gak
 * boleh menimpa record versi lebih baru.
 */
export const records = sqliteTable(
  "records",
  {
    userId: text("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    kind: text("kind").notNull(),
    key: text("key").notNull(),
    data: text("data"),
    updatedAt: integer("updated_at").notNull(),
    deleted: integer("deleted", { mode: "boolean" }).notNull().default(false),
    schemaVersion: integer("schema_version").notNull(),
    seq: integer("seq").notNull(),
  },
  // Index (user_id, seq): pull baca cuma baris setelah cursor, bukan semua record user.
  (t) => [primaryKey({ columns: [t.userId, t.kind, t.key] }), index("records_user_seq").on(t.userId, t.seq)],
);
