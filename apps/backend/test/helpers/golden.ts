import { env } from "cloudflare:test";
import { backendWireErrorCode, errorBodySchema } from "@luma/contracts/errors";
import { recordResponse, type Recorded } from "@luma/worker-kit/testing/golden";
import type { ZodType } from "zod";
import { callWithBudget } from "./budget";

export { GOLDEN_NOW, goldenJson, normalize, type Recorded } from "@luma/worker-kit/testing/golden";

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

const errorSchema = errorBodySchema.extend({
  error: errorBodySchema.shape.error.extend({ code: backendWireErrorCode }),
});

export async function record(
  request: Request,
  overrides: Partial<Env> = {},
  contract?: ZodType,
): Promise<Recorded> {
  const r2 = countingR2(overrides.BUCKET ?? env.BUCKET);
  const { response, d1Queries, subrequests } = await callWithBudget(request, {
    ...overrides,
    BUCKET: r2.bucket,
  });
  return recordResponse(
    response,
    { d1Queries, fetches: subrequests, r2Ops: r2.count() },
    errorSchema,
    contract,
  );
}
