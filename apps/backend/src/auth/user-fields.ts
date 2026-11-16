// Kolom tambahan tabel users milik Luma. Dipakai src/auth/auth.ts dan
// scripts/auth-schema.config.ts supaya schema hasil generate selalu sama.

export const userAdditionalFields = {
  /** Cabut akses AI subsidi (docs/backend.md, Batas & pengaman). Gak bisa diisi dari sign-up. */
  banned: { type: "boolean", defaultValue: false, required: false, input: false, returned: false },
} as const;
