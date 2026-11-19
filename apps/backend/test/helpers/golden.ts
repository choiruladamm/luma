import { env } from "cloudflare:test";
import { callWithBudget } from "./budget";

/** Fixed clock for golden runs: timestamps in responses are recorded as real values. */
export const GOLDEN_NOW = new Date("2026-11-20T03:00:00.000Z");

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** Better Auth ids and tokens: 32 random alphanumerics. */
const AUTH_ID = /^[A-Za-z0-9]{32}$/;

/** Replaces generated values (random ids and tokens) with placeholders. */
export function normalize(value: unknown): unknown {
  if (typeof value === "string") {
    if (UUID.test(value)) return "<uuid>";
    if (AUTH_ID.test(value)) return "<auth-id>";
    return value;
  }
  if (Array.isArray(value)) return value.map(normalize);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, normalize(v)]));
  }
  return value;
}

/** Counts R2 binding calls (put, get, head, list, delete). */
function countingR2(bucket: R2Bucket) {
  let ops = 0;
  const proxy = new Proxy(bucket, {
    get(target, prop) {
      const value = Reflect.get(target, prop, target);
      if (typeof value !== "function") return value;
      return (...args: unknown[]) => {
        ops++;
        const fn: (...a: unknown[]) => unknown = value;
        return fn.apply(target, args);
      };
    },
  });
  return { bucket: proxy, count: () => ops };
}

/** A cookie keeps its name and attributes; only the generated value is masked. */
const maskCookie = (cookie: string) => cookie.replace(/^([^=]+)=[^;]*/, "$1=<random>");

async function digest(text: string) {
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(hash)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** One response as recorded in a golden file: status, headers, cookies, body, and request budget. */
export type Recorded = {
  status: number;
  headers: Record<string, string>;
  cookies: string[];
  body: unknown;
  d1Queries: number;
  /** Outbound `fetch` calls (Google, OpenRouter). */
  fetches: number;
  r2Ops: number;
};

export async function record(request: Request, overrides: Partial<Env> = {}): Promise<Recorded> {
  const r2 = countingR2(overrides.BUCKET ?? env.BUCKET);
  const { response, d1Queries, subrequests } = await callWithBudget(request, {
    ...overrides,
    BUCKET: r2.bucket,
  });
  const headers = Object.fromEntries(
    [...response.headers]
      .filter(([k]) => k !== "set-cookie")
      .map(([k, v]) => [k, k === "x-request-id" || k === "set-auth-token" ? "<present>" : v]),
  );
  const type = response.headers.get("content-type") ?? "";
  const text = await response.text();
  let body: unknown = text;
  if (type.includes("application/json")) body = normalize(JSON.parse(text));
  else if (type.includes("text/html")) body = { sha256: await digest(text), length: text.length };
  return {
    status: response.status,
    headers,
    cookies: response.headers.getSetCookie().map(maskCookie),
    body,
    d1Queries,
    fetches: subrequests,
    r2Ops: r2.count(),
  };
}

/** Golden JSON: a stable, reviewable diff when behavior changes. */
export const goldenJson = (steps: Record<string, Recorded>) =>
  `${JSON.stringify(steps, null, 2)}\n`;
