// Extra columns on Luma's users table. Shared by src/auth/auth.ts and
// scripts/auth-schema.config.ts so the generated schema always matches.

export const userAdditionalFields = {
  /** Revokes subsidized AI access (docs/backend.md, AI subsidy). Can't be set at sign-up. */
  banned: { type: "boolean", defaultValue: false, required: false, input: false, returned: false },
} as const;
