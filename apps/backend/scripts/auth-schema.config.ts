// Config khusus `npx auth@latest generate` (CLI butuh instance statis).
// Plugin dan opsi yang mempengaruhi schema harus sama dengan src/auth/auth.ts.
// Jalankan: bunx auth@latest generate --config scripts/auth-schema.config.ts --output src/db/auth-schema.ts -y
import { drizzleAdapter } from "@better-auth/drizzle-adapter";
import { betterAuth } from "better-auth";
import { bearer } from "better-auth/plugins";
import { drizzle } from "drizzle-orm/d1";

export const auth = betterAuth({
  database: drizzleAdapter(drizzle({} as D1Database), { provider: "sqlite", usePlural: true }),
  emailAndPassword: { enabled: true },
  socialProviders: { google: { clientId: "x", clientSecret: "x" } },
  plugins: [bearer()],
});
