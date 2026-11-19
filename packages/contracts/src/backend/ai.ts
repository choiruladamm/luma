import { z } from "zod";

/** `POST /v1/ai/key` body. */
export const keyRequest = z.strictObject({ rotate: z.boolean().optional() });

export const keyResponse = z.strictObject({
  key: z.string(),
  expiresAt: z.string(),
  dailyLimitUsd: z.number(),
});
export type IssuedKey = z.infer<typeof keyResponse>;

export const usageResponse = z.strictObject({
  dailyLimitUsd: z.number(),
  remainingUsd: z.number(),
  usedTodayUsd: z.number(),
  resetsAt: z.string(),
});
export type AiUsage = z.infer<typeof usageResponse>;

export const configResponse = z.strictObject({
  chatModels: z.array(z.string()),
  embeddingModels: z.array(z.string()),
  dailyLimitUsd: z.number(),
});
export type AiPublicConfig = z.infer<typeof configResponse>;
