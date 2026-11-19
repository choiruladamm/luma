import { Hono } from "hono";
import { getAuth } from "../../auth/auth";
import type { AppEnv } from "../../env";
import { normalizeAuthError } from "@luma/worker-kit/errors";
import { limitBody } from "@luma/worker-kit/middleware";

/** Auth bodies are small (email, password, idToken). */
const AUTH_BODY_LIMIT = 16 * 1024;

/**
 * Better Auth endpoints that are exposed: only those the app uses (auth_service.dart).
 * The rest (update-user, change-email, list-sessions, etc.) return 404, so the attack
 * surface doesn't grow each time Better Auth adds an endpoint.
 * Google goes through a native idToken (`sign-in/social`), with no redirect callback.
 */
export const AUTH_PATHS = [
  "/sign-up/email",
  "/sign-in/email",
  "/sign-in/social",
  "/sign-out",
] as const;

export const auth = new Hono<AppEnv>()
  .use(limitBody(AUTH_BODY_LIMIT))
  .on("POST", [...AUTH_PATHS], async (c) =>
    normalizeAuthError(await getAuth(c.env).handler(c.req.raw)),
  );
