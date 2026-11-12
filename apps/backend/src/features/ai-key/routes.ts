import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { z } from "zod";
import { openRouterAdmin } from "../../clients/openrouter";
import { createDb } from "../../db/client";
import type { AppEnv } from "../../env";
import { ApiError } from "../../lib/errors";
import { limitBody } from "../../middleware/body-limit";
import { killSwitch } from "../../middleware/kill-switch";
import { rateLimit } from "../../middleware/rate-limit";
import { requireSession } from "../../middleware/session";
import { aiConfig, issueKey, usage } from "./service";

const keyBody = z.object({ rotate: z.boolean().optional() }).strict();

export const ai = new Hono<AppEnv>()
  .use(killSwitch("AI_KEY_ENABLED"), requireSession)
  .post(
    "/key",
    rateLimit((c) => `user:${c.get("user").id}`),
    limitBody(1024),
    zValidator("json", keyBody, (result) => {
      if (!result.success) throw new ApiError(400, "BAD_REQUEST", "Body must be {\"rotate\"?: boolean}");
    }),
    async (c) => {
      const { rotate } = c.req.valid("json");
      const issued = await issueKey(
        createDb(c.env.DB),
        openRouterAdmin(c.env.OPENROUTER_MANAGEMENT_KEY),
        aiConfig(c.env),
        c.get("user").id,
        { rotate },
      );
      return c.json(issued);
    },
  )
  .get("/usage", async (c) =>
    c.json(
      await usage(
        createDb(c.env.DB),
        openRouterAdmin(c.env.OPENROUTER_MANAGEMENT_KEY),
        aiConfig(c.env),
        c.get("user").id,
      ),
    ),
  )
  .get("/config", (c) => {
    const { chatModels, embeddingModels, dailyLimitUsd } = aiConfig(c.env);
    return c.json({ chatModels, embeddingModels, dailyLimitUsd });
  });
