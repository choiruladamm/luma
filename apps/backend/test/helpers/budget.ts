import { createExecutionContext, env, waitOnExecutionContext } from "cloudflare:test";
import { vi } from "vitest";
import { countingD1 } from "@luma/worker-kit/testing/d1";
import { app } from "../../src/app";

export { countingD1 };

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
