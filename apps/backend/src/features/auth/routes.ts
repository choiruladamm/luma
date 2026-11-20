import { Hono } from "hono";
import { getAuth } from "../../auth/auth";
import type { AppEnv } from "../../env";
import { normalizeAuthError } from "@luma/worker-kit/errors";
import { snakeJson, toCamel } from "@luma/worker-kit/case";
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

/** Better Auth's `basePath` (auth.ts): it matches on this prefix whichever version was called. */
const BASE_PATH = "/v1/auth";

/**
 * `/v2/auth/*` speaks snake_case: the request is rewritten to Better Auth's base path with its
 * JSON body keys in camelCase (small: `limitBody` ran first), and its JSON answer converted back.
 * A body that isn't JSON goes through untouched for Better Auth to reject.
 */
async function toBetterAuth(req: Request) {
  const url = new URL(req.url);
  url.pathname = url.pathname.replace(/^\/v2\/auth/, BASE_PATH);
  const headers = new Headers(req.headers);
  headers.delete("content-length");
  const text = await req.text();
  let body = text;
  if (req.headers.get("content-type")?.includes("json")) {
    try {
      body = JSON.stringify(toCamel(JSON.parse(text)));
    } catch {
      // Malformed JSON: Better Auth reports it.
    }
  }
  return new Request(url, { method: req.method, headers, body: body || null });
}

export const auth = new Hono<AppEnv>()
  .use(limitBody(AUTH_BODY_LIMIT))
  .on("POST", [...AUTH_PATHS], async (c) => {
    const ba = getAuth(c.env);
    if (c.var.wire === "v1") return normalizeAuthError(await ba.handler(c.req.raw));
    return snakeJson(await normalizeAuthError(await ba.handler(await toBetterAuth(c.req.raw))));
  });
