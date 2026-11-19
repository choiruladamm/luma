import { drizzleAdapter } from "@better-auth/drizzle-adapter";
import { betterAuth } from "better-auth";
import { APIError } from "better-auth/api";
import { userAdditionalFields } from "@backend/auth/user-fields";
import { createDb } from "@backend/db/client";
import * as schema from "@backend/db/schema";
import { isAdmin } from "./admin";
import { findUserForAdminCheck } from "./session";

const DAY_S = 24 * 60 * 60;
/** Idle limit: unused for 7 days → sign in again. Used sessions slide (see `updateAge`). */
export const SESSION_EXPIRES_IN_S = 7 * DAY_S;
/** Slide at most once a day: 1 D1 write per admin per day. */
export const SESSION_UPDATE_AGE_S = DAY_S;

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
    // Sliding session: get-session pushes the expiry (DB row + cookie) once a day while used. Better
    // Auth has no absolute limit; the 30-day cap is `SESSION_MAX_AGE_MS` in session.ts.
    session: { expiresIn: SESSION_EXPIRES_IN_S, updateAge: SESSION_UPDATE_AGE_S },
    // Callback errors (e.g. non-admin) go back to the SPA login page, not Better Auth's error page.
    onAPIError: { errorURL: "/login" },
    databaseHooks: {
      user: {
        // Only an admin's first Google sign-in creates an account (so a fresh env needs no app
        // sign-in or invite first). The Google account row comes with it, so the mobile app later
        // signs this user in as an existing account, without an invite.
        create: {
          before: async (user) => {
            if (!isAdmin(env, { email: user.email, emailVerified: user.emailVerified })) {
              throw new APIError("FORBIDDEN", {
                code: "FORBIDDEN",
                message: "Dashboard creates accounts for admins only",
              });
            }
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
