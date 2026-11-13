import { drizzleAdapter } from "@better-auth/drizzle-adapter";
import { betterAuth } from "better-auth";
import { APIError } from "better-auth/api";
import { bearer } from "better-auth/plugins";
import { createDb } from "../db/client";
import * as schema from "../db/schema";
import { assignInviteCode, consumeInviteCode, INVITE_HEADER } from "./invite";
import { hashPassword, verifyPassword } from "./password";
import { SESSION_EXPIRES_IN_MS, SESSION_UPDATE_AGE_MS } from "./session";
import { userAdditionalFields } from "./user-fields";

const inviteFrom = (headers: Headers | undefined) => headers?.get(INVITE_HEADER)?.trim() ?? "";

/** Google aktif kalau client ID diisi (web,ios,android dipisah koma). */
const googleProvider = (env: Env) =>
  env.GOOGLE_CLIENT_IDS
    ? {
        google: {
          clientId: env.GOOGLE_CLIENT_IDS.split(",").map((id) => id.trim()),
          clientSecret: env.GOOGLE_CLIENT_SECRET ?? "",
        },
      }
    : {};

let cached: { env: Env; auth: Auth } | undefined;

/**
 * Bikin instance Better Auth itu mahal (puluhan ms CPU), jadi dipakai ulang per
 * isolate selama objek `env` sama. Bukan state per request: isinya cuma konfigurasi
 * dan binding.
 */
export function getAuth(env: Env): Auth {
  if (cached?.env !== env) cached = { env, auth: createAuth(env) };
  return cached.auth;
}

/** Opsi yang mempengaruhi schema harus sama dengan scripts/auth-schema.config.ts. */
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
    // Rate limit pakai binding Workers per IP (middleware app), bukan storage Better Auth.
    rateLimit: { enabled: false },
    // Login wajib + offline: sesi panjang, diperpanjang paling sering sekali sehari (1 tulis D1).
    session: { expiresIn: SESSION_EXPIRES_IN_MS / 1000, updateAge: SESSION_UPDATE_AGE_MS / 1000 },
    databaseHooks: {
      user: {
        create: {
          before: async (user, ctx) => {
            if (!inviteRequired) return;
            const code = inviteFrom(ctx?.headers);
            if (!code) {
              throw new APIError("FORBIDDEN", {
                code: "INVITE_CODE_REQUIRED",
                message: "New accounts need an invite code",
              });
            }
            const result = await consumeInviteCode(db, code);
            if (result === "used") {
              throw new APIError("FORBIDDEN", {
                code: "INVITE_CODE_USED",
                message: "Invite code has already been used",
              });
            }
            if (result === "invalid") {
              throw new APIError("FORBIDDEN", {
                code: "INVALID_INVITE_CODE",
                message: "Invite code is invalid",
              });
            }
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
