import { dashboardErrorCode, errorBodySchema } from "@luma/contracts/errors";
import { recordResponse, type Recorded } from "@luma/worker-kit/testing/golden";
import { vi } from "vitest";
import type { ZodType } from "zod";
import { call } from "./app";

export { GOLDEN_NOW, goldenJson, normalize, type Recorded } from "@luma/worker-kit/testing/golden";

const errorSchema = errorBodySchema.extend({
  error: errorBodySchema.shape.error.extend({ code: dashboardErrorCode }),
});

export async function record(
  path: string,
  init: RequestInit = {},
  overrides: Partial<Env> = {},
  contract?: ZodType,
): Promise<Recorded> {
  const fetchSpy = vi.spyOn(globalThis, "fetch");
  try {
    const { response, d1Queries } = await call(path, { redirect: "manual", ...init }, overrides);
    return await recordResponse(
      response,
      { d1Queries, fetches: fetchSpy.mock.calls.length },
      errorSchema,
      contract,
    );
  } finally {
    fetchSpy.mockRestore();
  }
}
