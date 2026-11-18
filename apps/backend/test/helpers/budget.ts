import { createExecutionContext, env, waitOnExecutionContext } from "cloudflare:test";
import { vi } from "vitest";
import { app } from "../../src/app";

/** Wraps D1 and counts executed statements (prepare/exec, plus the contents of a batch). */
export function countingD1(d1: D1Database) {
  let queries = 0;
  const proxy = new Proxy(d1, {
    get(target, prop) {
      const value = Reflect.get(target, prop, target);
      if (typeof value !== "function") return value;
      if (prop === "prepare" || prop === "exec") {
        return (...args: unknown[]) => {
          queries++;
          const fn: (...a: unknown[]) => unknown = value;
          return fn.apply(target, args);
        };
      }
      return value.bind(target);
    },
  });
  return { db: proxy, count: () => queries };
}

export type Budget = { response: Response; d1Queries: number; subrequests: number };

/**
 * Calls the app with a counted D1 and a counted outbound fetch, to check
 * the per-request budget (docs/budgets.md, Per-action budgets).
 */
export async function callWithBudget(
  request: Request,
  overrides: Partial<Env> = {},
): Promise<Budget> {
  const d1 = countingD1(env.DB);
  const fetchSpy = vi.spyOn(globalThis, "fetch");
  try {
    const ctx = createExecutionContext();
    const response = await app.fetch(request, { ...env, DB: d1.db, ...overrides }, ctx);
    await waitOnExecutionContext(ctx);
    return { response, d1Queries: d1.count(), subrequests: fetchSpy.mock.calls.length };
  } finally {
    fetchSpy.mockRestore();
  }
}
