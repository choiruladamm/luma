import { createMiddleware } from "hono/factory";
import { toCamel, toSnake } from "@luma/worker-kit/case";
import type { AppEnv, Wire } from "../env";

/** Sets `c.var.wire` for the mount, so routes and the adapter know the version. */
export const wire = (version: Wire) =>
  createMiddleware<AppEnv>(async (c, next) => {
    c.set("wire", version);
    await next();
  });

/** The one opaque payload in a JSON request: sync's Drift JSON (docs/backend.md, API versions). */
const OPAQUE_REQUEST = ["records.*.data"];

const isOpaque = (at: string[]) =>
  OPAQUE_REQUEST.some((pattern) => {
    const parts = pattern.split(".");
    return parts.length === at.length && parts.every((part, i) => part === "*" || part === at[i]);
  });

/** Whether a `/v1` body already has a snake_case key outside the opaque payload. */
function hasSnakeKey(value: unknown, path: string[] = []): boolean {
  if (Array.isArray(value)) return value.some((v, i) => hasSnakeKey(v, [...path, String(i)]));
  if (value === null || typeof value !== "object") return false;
  return Object.entries(value).some(([k, v]) => {
    const at = [...path, k];
    return !isOpaque(at) && (k.includes("_") || hasSnakeKey(v, at));
  });
}

/**
 * `/v1` speaks camelCase only. A body that already has a snake_case key becomes `null`, which every
 * route's schema rejects with the route's own message, as the strict camelCase schema did before
 * this adapter; and `schemaVersion` plus `schema_version` can't merge into one key.
 */
const toV2 = (body: unknown) => (hasSnakeKey(body) ? null : toSnake(body, OPAQUE_REQUEST));

/**
 * Temporary, until `/v1` is removed (#265): the routers and contracts speak snake_case, and this lets
 * the app installs already in production keep talking camelCase (docs/backend.md, API versions).
 * - Request: the JSON body is parsed once, lazily, where `validate` asks for it (after `limitBody`
 *   has rejected an oversized one), and its keys are converted to snake_case on the way. Hono's
 *   `bodyCache.json` is no shortcut: `req.json()` re-reads the text and parses it again.
 * - Response: a 2xx JSON body is converted to camelCase. Errors have the same body on both
 *   versions, non-JSON passes through, and a route that built its body for `wire` (sync pull, a
 *   500-record string made by SQL) is never parsed.
 * Better Auth's `/v1/auth/*` is camelCase natively and is left alone.
 */
export const v1Adapter = createMiddleware<AppEnv>(async (c, next) => {
  if (c.req.path.startsWith("/v1/auth/")) return next();

  const parse = c.req.json.bind(c.req);
  let body: Promise<unknown> | undefined;
  // oxlint-disable-next-line typescript/no-unsafe-type-assertion -- `req.json<T>()` is an unchecked cast by design; `validate` is the caller.
  c.req.json = <T>() => (body ??= parse().then(toV2)) as Promise<T>;

  await next();

  const res = c.res;
  if (
    c.get("wireDone") ||
    res.status >= 400 ||
    !res.headers.get("content-type")?.includes("json")
  ) {
    return;
  }
  c.res = new Response(JSON.stringify(toCamel(await res.json())), res);
});
