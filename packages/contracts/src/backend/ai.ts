import { z } from "zod";

/** `POST /v2/ai/key` body. */
export const keyRequest = z.strictObject({ rotate: z.boolean().optional() });

export const keyResponse = z.strictObject({
  key: z.string(),
  expires_at: z.string(),
  daily_limit_usd: z.number(),
});
export type IssuedKey = z.infer<typeof keyResponse>;

export const usageResponse = z.strictObject({
  daily_limit_usd: z.number(),
  remaining_usd: z.number(),
  used_today_usd: z.number(),
  resets_at: z.string(),
});
export type AiUsage = z.infer<typeof usageResponse>;

export const configResponse = z.strictObject({
  chat_models: z.array(z.string()),
  embedding_models: z.array(z.string()),
  daily_limit_usd: z.number(),
});
export type AiPublicConfig = z.infer<typeof configResponse>;
