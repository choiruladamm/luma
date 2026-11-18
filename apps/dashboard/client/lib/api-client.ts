import { hc } from "hono/client";
import type { AppType } from "../../worker/index";

/**
 * Typed client for the dashboard API (same origin, cookies sent automatically). The JSON
 * content-type is global because the worker rejects mutations without it, body or not.
 * `X-Requested-With` makes Cloudflare Access answer an expired session with 401 instead of a
 * cross-origin redirect that fetch can't follow (see `toApiError`).
 */
export const api = hc<AppType>("/", {
  headers: { "content-type": "application/json", "x-requested-with": "XMLHttpRequest" },
}).api;
