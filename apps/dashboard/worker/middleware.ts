import { getSignedCookie } from "hono/cookie";
import { createMiddleware } from "hono/factory";
import { createDb } from "../../backend/src/db/client";
import { isAdmin } from "./auth";
import type { AppEnv } from "./env";
import { ApiError } from "./errors";
import { findSession } from "./repo";

export const RATE_LIMIT_PERIOD_SECONDS = 60;

export const requestId = createMiddleware<AppEnv>(async (c, next) => {
  const id = crypto.randomUUID();
  c.set("requestId", id);
  c.header("x-request-id", id);
  await next();
});

/** Semua respons, termasuk error dan respons Better Auth. */
export const securityHeaders = createMiddleware<AppEnv>(async (c, next) => {
  await next();
  c.res.headers.set("Content-Security-Policy", "default-src 'self'; frame-ancestors 'none'");
  c.res.headers.set("X-Content-Type-Options", "nosniff");
});

export const rateLimitIp = createMiddleware<AppEnv>(async (c, next) => {
  const ip = c.req.header("cf-connecting-ip") ?? "unknown";
  const { success } = await c.env.RATE_LIMITER.limit({ key: `ip:${ip}` });
  if (!success) {
    throw new ApiError(429, "RATE_LIMITED", "Too many requests", {
      "Retry-After": String(RATE_LIMIT_PERIOD_SECONDS),
    });
  }
  await next();
});

/** Nama cookie sesi Better Auth: prefix `__Secure-` kalau baseURL https. */
export const sessionCookieName = (env: Env) =>
  env.BETTER_AUTH_URL.startsWith("https://") ? "__Secure-better-auth.session_token" : "better-auth.session_token";

/**
 * Sesi cookie + admin, dipasang global di `/api/*` (selain `/api/auth/*`), jadi
 * route baru otomatis terlindungi. Cookie dicek tanda tangannya dulu: tanpa
 * cookie / tanda tangan salah → 401 tanpa menyentuh D1. Instance Better Auth
 * gak dibangun di sini (mahal CPU); cukup satu query join.
 */
export const requireAdmin = createMiddleware<AppEnv>(async (c, next) => {
  const token = await getSignedCookie(c, c.env.BETTER_AUTH_SECRET, sessionCookieName(c.env));
  if (!token) throw new ApiError(401, "UNAUTHORIZED", "Sign in required");

  const db = createDb(c.env.DB);
  const session = await findSession(db, token);
  if (!session || session.expiresAt.getTime() <= Date.now()) {
    throw new ApiError(401, "UNAUTHORIZED", "Sign in required");
  }
  // Dicek ulang tiap request: email dihapus dari ADMIN_EMAILS → sesi lama langsung ditolak.
  if (!isAdmin(c.env, session)) throw new ApiError(403, "FORBIDDEN", "Admin only");

  c.set("db", db);
  c.set("admin", { id: session.id, email: session.email });
  await next();
});

const SAFE_METHODS = new Set(["GET", "HEAD", "OPTIONS"]);

/** CSRF: mutasi wajib JSON dan `Origin` persis domain dashboard. */
export const requireSameOriginJson = createMiddleware<AppEnv>(async (c, next) => {
  if (!SAFE_METHODS.has(c.req.method)) {
    const json = c.req.header("content-type")?.split(";")[0]?.trim().toLowerCase() === "application/json";
    const origin = c.req.header("origin") === new URL(c.env.BETTER_AUTH_URL).origin;
    if (!json || !origin) throw new ApiError(403, "FORBIDDEN", "Mutations need JSON from the dashboard origin");
  }
  await next();
});
