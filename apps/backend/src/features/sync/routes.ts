import { Hono } from "hono";
import { limitBody, validate } from "@luma/worker-kit/middleware";
import {
  MAX_PULL_RECORDS,
  MAX_PUSH_RECORDS,
  pullQuery,
  pushRequest,
} from "@luma/contracts/backend/sync";
import type { AppEnv } from "../../env";
import { featureGuard } from "../../middleware/guard";
import { JSON_BODY_LIMIT } from "../../middleware/policy";
import { pull, push, syncLimits } from "./service";

export const sync = new Hono<AppEnv>()
  .use(...featureGuard("SYNC_ENABLED"))
  .post(
    "/push",
    limitBody(JSON_BODY_LIMIT),
    validate(
      "json",
      pushRequest,
      `Body must be {"schemaVersion", "records": [≤${MAX_PUSH_RECORDS}]}`,
    ),
    async (c) =>
      c.json(await push(c.env.DB, c.get("user").id, c.req.valid("json"), syncLimits(c.env))),
  )
  .get(
    "/pull",
    validate("query", pullQuery, `Query must be ?since=<seq>&limit=<1..${MAX_PULL_RECORDS}>`),
    async (c) => {
      const { since, limit } = c.req.valid("query");
      return c.body(await pull(c.env.DB, c.get("user").id, since, limit), 200, {
        "content-type": "application/json",
      });
    },
  );
