import { createExecutionContext, env, waitOnExecutionContext } from "cloudflare:test";
import { countingD1 } from "@luma/worker-kit/testing/d1";
import { app } from "../../worker/index";

export const ORIGIN = "https://luma-admin-dev.chrl.cloud";

/** Call the app with overridable `env`, counting D1 queries. */
export async function call(
  input: string | Request,
  init: RequestInit = {},
  overrides: Partial<Env> = {},
) {
  const d1 = countingD1(env.DB);
  const request = typeof input === "string" ? new Request(new URL(input, ORIGIN), init) : input;
  const ctx = createExecutionContext();
  const response = await app.fetch(request, { ...env, DB: d1.db, ...overrides }, ctx);
  await waitOnExecutionContext(ctx);
  return { response, d1Queries: d1.count() };
}

export const errorCode = async (res: Response) =>
  (await res.json<{ error: { code: string } }>()).error.code;
