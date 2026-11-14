import { drizzleAdapter } from "@better-auth/drizzle-adapter";
import { betterAuth } from "better-auth";
import { APIError } from "better-auth/api";
import { userAdditionalFields } from "../../../backend/src/auth/user-fields";
import { createDb } from "../../../backend/src/db/client";
import * as schema from "../../../backend/src/db/schema";
import { isAdmin } from "./admin";
import { findUserForAdminCheck } from "./session";

export const SESSION_EXPIRES_IN_S = 12 * 60 * 60;

let cached: { env: Env; auth: Auth } | undefined;

/** Building Better Auth is expensive (tens of ms CPU): reuse it per isolate while `env` is the same object. */
export function getAuth(env: Env): Auth {
  if (cached?.env !== env) cached = { env, auth: createAuth(env) };
  return cached.auth;
}

/**
 * Second Better Auth instance on the backend D1: Google redirect login for admins only,
 * session cookies signed with the dashboard's own secret (mobile app tokens don't work).
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
    // OAuth state lives in an encrypted cookie: sign-in/social doesn't write D1.
    account: { storeStateStrategy: "cookie" },
    // Rate limiting is the per-IP Workers binding (middleware), not Better Auth storage.
    rateLimit: { enabled: false },
    // Short admin sessions, never extended: sign in again after 12 hours.
    session: { expiresIn: SESSION_EXPIRES_IN_S, disableSessionRefresh: true },
    // Callback errors (e.g. non-admin) go back to the SPA login page, not Better Auth's error page.
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
