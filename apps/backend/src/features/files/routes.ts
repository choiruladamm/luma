import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../../env";
import { ApiError } from "../../lib/errors";
import { uploadSize } from "../../lib/storage";
import { limitBody } from "../../middleware/body-limit";
import { featureGuard } from "../../middleware/guard";
import { FILE_NAME, getFile, missingFiles, putFile } from "./service";

const missingBody = z.object({ names: z.array(z.string().regex(FILE_NAME)).max(1000) }).strict();

const fileName = (name: string) => {
  if (!FILE_NAME.test(name)) throw new ApiError(400, "BAD_REQUEST", "Invalid file name");
  return name;
};

export const files = new Hono<AppEnv>()
  .use(...featureGuard("BACKUP_ENABLED"))
  .post(
    "/missing",
    limitBody(256 * 1024),
    zValidator("json", missingBody, (result) => {
      if (!result.success) throw new ApiError(400, "BAD_REQUEST", 'Body must be {"names": string[≤1000]}');
    }),
    async (c) =>
      c.json({ missing: await missingFiles(c.env.BUCKET, c.get("user").id, c.req.valid("json").names) }),
  )
  .put("/:name", async (c) => {
    const name = fileName(c.req.param("name"));
    const size = uploadSize(c.req.header("content-length"));
    const stored = await putFile(
      c.var.db,
      c.env.BUCKET,
      Number(c.env.USER_STORAGE_BYTES),
      c.get("user").id,
      name,
      size,
      c.req.raw.body,
    );
    return c.json(stored);
  })
  .get("/:name", async (c) => {
    const object = await getFile(c.env.BUCKET, c.get("user").id, fileName(c.req.param("name")));
    return c.body(object.body, 200, { "content-length": String(object.size) });
  });
