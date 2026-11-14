import { drizzleAdapter } from "@better-auth/drizzle-adapter";
import { betterAuth } from "better-auth";
import { APIError } from "better-auth/api";
import { userAdditionalFields } from "../../backend/src/auth/user-fields";
import { createDb } from "../../backend/src/db/client";
import * as schema from "../../backend/src/db/schema";
import { findUserForAdminCheck } from "./repo";

export const SESSION_EXPIRES_IN_S = 12 * 60 * 60;

/**
 * Admin = email persis ada di `ADMIN_EMAILS` (setelah trim + lowercase) dan sudah
 * diverifikasi. `ADMIN_EMAILS` kosong → gak ada admin (fail closed).
 */
export function isAdmin(env: Pick<Env, "ADMIN_EMAILS">, user: { email: string; emailVerified: boolean }) {
  if (!user.emailVerified) return false;
  const email = user.email.trim().toLowerCase();
  return env.ADMIN_EMAILS.split(",").some((item) => {
    const admin = item.trim().toLowerCase();
    return admin !== "" && admin === email;
  });
}

let cached: { env: Env; auth: Auth } | undefined;

/** Instance Better Auth mahal dibikin (puluhan ms CPU): dipakai ulang per isolate selama `env` sama. */
export function getAuth(env: Env): Auth {
  if (cached?.env !== env) cached = { env, auth: createAuth(env) };
  return cached.auth;
}

/**
 * Instance Better Auth kedua di D1 backend: cuma login Google redirect buat admin,
 * cookie sesi ditandatangani secret dashboard sendiri (token app mobile gak berlaku).
 */
export function createAuth(env: Env) {
  const db = createDb(env.DB);

  return betterAuth({
    appName: "Luma Admin",
    baseURL: env.BETTER_AUTH_URL,
    basePath: "/api/auth",
    secret: env.BETTER_AUTH_SECRET,
    trustedOrigins: [env.BETTER_AUTH_URL],
    database: drizzleAdapter(db, { provider: "sqlite", usePlural: true, schema }),
    socialProviders: {
      google: { clientId: env.GOOGLE_CLIENT_ID, clientSecret: env.GOOGLE_CLIENT_SECRET },
    },
    user: { additionalFields: userAdditionalFields },
    // State OAuth di cookie terenkripsi: sign-in/social gak nulis D1.
    account: { storeStateStrategy: "cookie" },
    // Rate limit lewat binding Workers per IP (middleware), bukan storage Better Auth.
    rateLimit: { enabled: false },
    // Sesi admin pendek dan gak diperpanjang: lewat 12 jam login lagi.
    session: { expiresIn: SESSION_EXPIRES_IN_S, disableSessionRefresh: true },
    // Error callback (mis. non-admin) balik ke halaman login SPA, bukan halaman error Better Auth.
    onAPIError: { errorURL: "/login" },
    databaseHooks: {
      user: {
        create: {
          before: async () => {
            throw new APIError("FORBIDDEN", { code: "FORBIDDEN", message: "Dashboard cannot create accounts" });
          },
        },
      },
      session: {
        create: {
          before: async (session) => {
            const user = await findUserForAdminCheck(db, session.userId);
            if (!user || !isAdmin(env, user)) {
              throw new APIError("FORBIDDEN", { code: "FORBIDDEN", message: "Not an admin" });
            }
          },
        },
      },
    },
  });
}

export type Auth = ReturnType<typeof createAuth>;
