import { drizzleAdapter } from "@better-auth/drizzle-adapter";
import { betterAuth } from "better-auth";
import { APIError } from "better-auth/api";
import { bearer } from "better-auth/plugins";
import { createDb, type Db } from "@luma/core/db/client";
import * as schema from "@luma/core/db/schema";
import { csv } from "@luma/core/encoding";
import { assignInviteCode, consumeInviteCode, INVITE_HEADER } from "@luma/core/auth/invite";
import { hashPassword, verifyPassword } from "./password";
import { SESSION_EXPIRES_IN_MS, SESSION_UPDATE_AGE_MS } from "./session";
import { userAdditionalFields } from "@luma/core/auth/user-fields";

const inviteFrom = (headers: Headers | undefined) => headers?.get(INVITE_HEADER)?.trim() ?? "";

const INVITE_REJECTIONS = {
  required: { code: "INVITE_CODE_REQUIRED", message: "New accounts need an invite code" },
  used: { code: "INVITE_CODE_USED", message: "Invite code has already been used" },
  invalid: { code: "INVALID_INVITE_CODE", message: "Invite code is invalid" },
};

/** Spends the invite code before the user row is created; a missing, used, or unknown code is a 403. */
async function consumeInvite(db: Db, code: string) {
  if (!code) throw new APIError("FORBIDDEN", INVITE_REJECTIONS.required);
  const result = await consumeInviteCode(db, code);
  if (result !== "ok") throw new APIError("FORBIDDEN", INVITE_REJECTIONS[result]);
}

/** Google is enabled when client IDs are set (web, iOS, Android, comma-separated). */
const googleProvider = (env: Env) =>
  env.GOOGLE_CLIENT_IDS
    ? {
        google: {
          clientId: csv(env.GOOGLE_CLIENT_IDS),
          clientSecret: env.GOOGLE_CLIENT_SECRET ?? "",
        },
      }
    : {};

let cached: { env: Env; auth: Auth } | undefined;

/**
 * Creating a Better Auth instance is expensive (tens of ms of CPU), so it is reused per
 * isolate while the `env` object stays the same. Not per-request state: it holds only
 * configuration and bindings.
 */
export function getAuth(env: Env): Auth {
  if (cached?.env !== env) cached = { env, auth: createAuth(env) };
  return cached.auth;
}

/** Options that affect the schema must match packages/core/scripts/auth-schema.config.ts. */
export function createAuth(env: Env) {
  const db = createDb(env.DB);
  const inviteRequired = env.INVITE_REQUIRED === "true";

  return betterAuth({
    appName: "Luma",
    baseURL: env.BETTER_AUTH_URL,
    basePath: "/v1/auth",
    secret: env.BETTER_AUTH_SECRET,
    database: drizzleAdapter(db, { provider: "sqlite", usePlural: true, schema }),
    emailAndPassword: {
      enabled: env.ENV !== "prod",
      minPasswordLength: 8,
      password: { hash: hashPassword, verify: verifyPassword },
    },
    socialProviders: googleProvider(env),
    plugins: [bearer()],
    user: { additionalFields: userAdditionalFields },
    // Rate limiting uses the Workers binding per IP (app middleware), not Better Auth storage.
    rateLimit: { enabled: false },
    // Long sessions for login-required offline use: refreshed at most once a day (one D1 write).
    session: { expiresIn: SESSION_EXPIRES_IN_MS / 1000, updateAge: SESSION_UPDATE_AGE_MS / 1000 },
    databaseHooks: {
      user: {
        create: {
          before: async (user, ctx) => {
            if (!inviteRequired) return;
            await consumeInvite(db, inviteFrom(ctx?.headers));
          },
          after: async (user, ctx) => {
            const code = inviteFrom(ctx?.headers);
            if (inviteRequired && code) await assignInviteCode(db, code, user.id);
          },
        },
      },
    },
  });
}

export type Auth = ReturnType<typeof createAuth>;
