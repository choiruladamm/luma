import { z } from "zod";

/** Max rows per `POST /v2/usage` (docs/backend.md, Usage analytics). */
export const MAX_USAGE_ROWS = 500;

/** AI features by their code names (Artinya, Bedahin, Ngobrolin) plus reading time. */
export const USAGE_FEATURES = ["group", "breakdown", "chat", "reading"] as const;

/**
 * One rollup row: a local day × feature × model × book × key source. Empty strings stand for
 * "none" (a reading row has no model or key source, a chat outside a book has no book), because
 * they are part of the row's key and SQL never matches NULL to NULL.
 */
export const usageRow = z.strictObject({
  day: z.iso.date(),
  feature: z.enum(USAGE_FEATURES),
  model: z.string().max(200),
  book_key: z.string().max(200),
  book_title: z.string().max(500).nullable(),
  key_source: z.enum(["own", "subsidy", ""]),
  calls: z.number().int().min(0),
  failed: z.number().int().min(0),
  prompt_tokens: z.number().int().min(0),
  completion_tokens: z.number().int().min(0),
  /** Null when no call of the row reported a cost. */
  cost_usd: z.number().min(0).nullable(),
  reading_seconds: z.number().int().min(0),
});
export type UsageRow = z.infer<typeof usageRow>;

/** `POST /v2/usage` body. */
export const usageUploadRequest = z.strictObject({
  rows: z.array(usageRow).min(1).max(MAX_USAGE_ROWS),
});
export type UsageBody = z.infer<typeof usageUploadRequest>;

export const usageUploadResponse = z.strictObject({ applied: z.number().int() });
export type UsageResult = z.infer<typeof usageUploadResponse>;
