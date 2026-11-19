import { Hono } from "hono";
import { killSwitch, limitBody, validate } from "@luma/worker-kit/middleware";
import { type AiPublicConfig, keyRequest } from "@luma/contracts/backend/ai";
import type { AppEnv } from "../../env";
import { DISABLED_RETRY_AFTER_SECONDS } from "../../middleware/policy";
import { rateLimit } from "../../middleware/rate-limit";
import { requireSession } from "../../middleware/session";
import { aiConfig, issueKey, usage } from "./service";

export const ai = new Hono<AppEnv>()
  .use(killSwitch("AI_KEY_ENABLED", DISABLED_RETRY_AFTER_SECONDS), requireSession)
  .post(
    "/key",
    rateLimit((c) => `user:${c.get("user").id}`),
    limitBody(1024),
    validate("json", keyRequest, 'Body must be {"rotate"?: boolean}'),
    async (c) => {
      const { rotate } = c.req.valid("json");
      const issued = await issueKey(c.var.db, c.var.openrouter, aiConfig(c.env), c.get("user").id, {
        rotate,
      });
      return c.json(issued);
    },
  )
  .get("/usage", async (c) =>
    c.json(await usage(c.var.db, c.var.openrouter, aiConfig(c.env), c.get("user").id)),
  )
  .get("/config", (c) => {
    const { chatModels, embeddingModels, dailyLimitUsd } = aiConfig(c.env);
    return c.json<AiPublicConfig>({
      chat_models: chatModels,
      embedding_models: embeddingModels,
      daily_limit_usd: dailyLimitUsd,
    });
  });
