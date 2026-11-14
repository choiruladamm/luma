import { createExecutionContext, env, waitOnExecutionContext } from "cloudflare:test";
import { app } from "../../worker/index";

export const ORIGIN = "https://luma-admin-dev.chrl.cloud";

/** Wrap D1 and count statements (prepare/exec). */
function countingD1(d1: D1Database) {
  let queries = 0;
  const db = new Proxy(d1, {
    get(target, prop) {
      const value = Reflect.get(target, prop, target);
      if (typeof value !== "function") return value;
      if (prop === "prepare" || prop === "exec") {
        return (...args: unknown[]) => {
          queries++;
          return (value as (...a: unknown[]) => unknown).apply(target, args);
        };
      }
      return value.bind(target);
    },
  });
  return { db, count: () => queries };
}

/** Call the app with overridable `env`, counting D1 queries. */
export async function call(input: string | Request, init: RequestInit = {}, overrides: Partial<Env> = {}) {
  const d1 = countingD1(env.DB);
  const request = typeof input === "string" ? new Request(new URL(input, ORIGIN), init) : input;
  const ctx = createExecutionContext();
  const response = await app.fetch(request, { ...env, DB: d1.db, ...overrides }, ctx);
  await waitOnExecutionContext(ctx);
  return { response, d1Queries: d1.count() };
}

export const errorCode = async (res: Response) => ((await res.json()) as { error: { code: string } }).error.code;
