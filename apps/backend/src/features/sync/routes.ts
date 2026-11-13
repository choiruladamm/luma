import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../../env";
import { ApiError } from "../../lib/errors";
import { limitBody } from "../../middleware/body-limit";
import { featureGuard } from "../../middleware/guard";
import { KINDS } from "./merge";
import { MAX_PULL_RECORDS, MAX_PUSH_RECORDS, pull, push } from "./service";

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

const pullQuery = z.object({
  since: z.coerce.number().int().min(0),
  limit: z.coerce.number().int().min(1).max(MAX_PULL_RECORDS).default(MAX_PULL_RECORDS),
});

const pushBody = z
  .object({
    schemaVersion: z.number().int().min(1).max(100_000),
    records: z.array(record).min(1).max(MAX_PUSH_RECORDS),
  })
  .strict();

export const sync = new Hono<AppEnv>()
  .use(...featureGuard("SYNC_ENABLED"))
  .post(
    "/push",
    limitBody(),
    zValidator("json", pushBody, (result) => {
      if (!result.success) {
        throw new ApiError(400, "BAD_REQUEST", `Body must be {"schemaVersion", "records": [≤${MAX_PUSH_RECORDS}]}`);
      }
    }),
    async (c) => c.json(await push(c.env.DB, c.get("user").id, c.req.valid("json"))),
  )
  .get(
    "/pull",
    zValidator("query", pullQuery, (result) => {
      if (!result.success) {
        throw new ApiError(400, "BAD_REQUEST", `Query must be ?since=<seq>&limit=<1..${MAX_PULL_RECORDS}>`);
      }
    }),
    async (c) => {
      const { since, limit } = c.req.valid("query");
      return c.body(await pull(c.env.DB, c.get("user").id, since, limit), 200, {
        "content-type": "application/json",
      });
    },
  );
