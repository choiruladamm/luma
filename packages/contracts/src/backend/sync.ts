import { z } from "zod";

/** Max records per push (docs/sync-protocol.md, Sync quotas and compatibility). */
export const MAX_PUSH_RECORDS = 500;

/** Max records per pull page. */
export const MAX_PULL_RECORDS = 500;

export const KINDS = [
  "book",
  "reading_progress",
  "reading_session",
  "ai_result",
  "ai_breakdown",
  "setting",
  "chat_session",
  "chat_turn",
] as const;
export type Kind = (typeof KINDS)[number];

const kind = z.enum(KINDS);
/** Opaque: Drift's JSON keeps its own casing on both API versions (docs/sync-protocol.md). */
const data = z.record(z.string(), z.unknown());
export type Data = z.infer<typeof data>;

export const pushRecord = z
  .strictObject({
    kind,
    key: z.string().min(1).max(512),
    updated_at: z.iso.datetime(),
    deleted: z.boolean(),
    data: data.nullable(),
  })
  .refine((r) => r.deleted || r.data !== null, "data required unless deleted");
export type PushRecord = z.infer<typeof pushRecord>;

/** `POST /v2/sync/push` body. */
export const pushRequest = z.strictObject({
  schema_version: z.number().int().min(1).max(100_000),
  records: z.array(pushRecord).min(1).max(MAX_PUSH_RECORDS),
});
export type PushBody = z.infer<typeof pushRequest>;

export const pushResponse = z.strictObject({ seq: z.number().int(), applied: z.number().int() });
export type PushResult = z.infer<typeof pushResponse>;

/** `GET /v2/sync/pull` query. */
export const pullQuery = z.object({
  since: z.coerce.number().int().min(0),
  limit: z.coerce.number().int().min(1).max(MAX_PULL_RECORDS).default(MAX_PULL_RECORDS),
});

/** A stored record as pulled: the pushed fields plus the schema version it was written with and its `seq`. */
export const pullRecord = z.strictObject({
  kind,
  key: z.string(),
  updated_at: z.iso.datetime(),
  deleted: z.boolean(),
  data: data.nullable(),
  schema_version: z.number().int(),
  seq: z.number().int(),
});

export const pullResponse = z.strictObject({
  records: z.array(pullRecord),
  next_seq: z.number().int(),
  more: z.boolean(),
});
