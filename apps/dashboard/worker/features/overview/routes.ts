import { factory } from "../../env";
import { getOverview } from "./service";

// Chained so every route's types reach `AppType` (RPC client).
export const overview = factory
  .createApp()
  .get("/", async (c) => c.json(await getOverview(c.var.db, c.env, c.var.requestId)));
