import { Hono } from "hono";
import { limitBody, validate } from "@luma/worker-kit/middleware";
import { MAX_USAGE_ROWS, usageUploadRequest } from "@luma/contracts/backend/usage";
import type { AppEnv } from "../../env";
import { JSON_BODY_LIMIT } from "../../middleware/policy";
import { rateLimit } from "../../middleware/rate-limit";
import { requireSession } from "../../middleware/session";
import { saveUsage } from "./service";

export const usage = new Hono<AppEnv>()
  .use(
    requireSession,
    rateLimit((c) => `user:${c.get("user").id}`),
  )
  .post(
    "/",
    limitBody(JSON_BODY_LIMIT),
    validate("json", usageUploadRequest, `Body must be {"rows": [1..${MAX_USAGE_ROWS}]}`),
    async (c) => c.json(await saveUsage(c.env.DB, c.get("user").id, c.req.valid("json"))),
  );
