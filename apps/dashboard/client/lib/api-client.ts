import { hc } from "hono/client";
import type { AppType } from "../../worker/index";

/**
 * Typed client for the dashboard API (same origin, cookies sent automatically). The JSON
 * content-type is global because the worker rejects mutations without it, body or not.
 */
export const api = hc<AppType>("/", { headers: { "content-type": "application/json" } }).api;
