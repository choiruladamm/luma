// Config for `npx auth@latest generate`, whose CLI needs a static instance.
// Plugins and options that affect the schema must match apps/backend/src/auth/auth.ts.
// Run from packages/core: bunx auth@latest generate --config scripts/auth-schema.config.ts --output src/db/auth-schema.ts -y
import { drizzleAdapter } from "@better-auth/drizzle-adapter";
import { betterAuth } from "better-auth";
import { bearer } from "better-auth/plugins";
import { drizzle } from "drizzle-orm/d1";
import { userAdditionalFields } from "../src/auth/user-fields";

export const auth = betterAuth({
  // oxlint-disable-next-line typescript/no-unsafe-type-assertion -- the CLI only reads the schema; no D1 binding exists here
  database: drizzleAdapter(drizzle({} as D1Database), { provider: "sqlite", usePlural: true }),
  emailAndPassword: { enabled: true },
  socialProviders: { google: { clientId: "x", clientSecret: "x" } },
  plugins: [bearer()],
  user: { additionalFields: userAdditionalFields },
});
