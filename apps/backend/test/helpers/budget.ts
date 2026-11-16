import { createExecutionContext, env, waitOnExecutionContext } from "cloudflare:test";
import { vi } from "vitest";
import { app } from "../../src/app";

/** Bungkus D1 dan hitung statement yang dijalankan (prepare/exec, plus isi batch). */
export function countingD1(d1: D1Database) {
  let queries = 0;
  const proxy = new Proxy(d1, {
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
  return { db: proxy, count: () => queries };
}

export type Budget = { response: Response; d1Queries: number; subrequests: number };

/**
 * Panggil app dengan D1 terhitung dan fetch keluar terhitung, untuk cek
 * anggaran per request (docs/backend.md, Anggaran per aksi).
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
