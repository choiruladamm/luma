import { overviewUsageQuery } from "@luma/contracts/dashboard/overview";
import { validate } from "@luma/worker-kit/middleware";
import { factory } from "../../env";
import { getOverview, getUsageOverview } from "./service";

// Chained so every route's types reach `AppType` (RPC client).
export const overview = factory
  .createApp()
  .get("/", async (c) => c.json(await getOverview(c.var.db, c.env, c.var.requestId)))
  .get("/usage", validate("query", overviewUsageQuery), async (c) =>
    c.json(await getUsageOverview(c.var.db, c.req.valid("query").days)),
  );
