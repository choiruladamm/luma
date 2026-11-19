import { z } from "zod";

export const healthResponse = z.strictObject({ status: z.literal("ok"), env: z.string() });
export type HealthResponse = z.infer<typeof healthResponse>;
