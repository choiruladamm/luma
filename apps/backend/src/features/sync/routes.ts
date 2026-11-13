import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../../env";
import { ApiError } from "../../lib/errors";
import { limitBody } from "../../middleware/body-limit";
import { killSwitch } from "../../middleware/kill-switch";
import { rateLimit } from "../../middleware/rate-limit";
import { requireSession } from "../../middleware/session";
import { KINDS } from "./merge";
import { MAX_PUSH_RECORDS, push } from "./service";

const record = z
  .object({
    kind: z.enum(KINDS),
    key: z.string().min(1).max(512),
    updatedAt: z.iso.datetime(),
    deleted: z.boolean(),
    data: z.record(z.string(), z.unknown()).nullable(),
  })
  .strict()
  .refine((r) => r.deleted || r.data !== null, "data required unless deleted");

const pushBody = z
  .object({
    schemaVersion: z.number().int().min(1).max(100_000),
    records: z.array(record).min(1).max(MAX_PUSH_RECORDS),
  })
  .strict();

export const sync = new Hono<AppEnv>()
  .use(killSwitch("SYNC_ENABLED"), requireSession, rateLimit((c) => `user:${c.get("user").id}`))
  .post(
    "/push",
    limitBody(),
    zValidator("json", pushBody, (result) => {
      if (!result.success) {
        throw new ApiError(400, "BAD_REQUEST", `Body must be {"schemaVersion", "records": [≤${MAX_PUSH_RECORDS}]}`);
      }
    }),
    async (c) => c.json(await push(c.env.DB, c.get("user").id, c.req.valid("json"))),
  );
