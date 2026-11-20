import { Hono } from "hono";
import { limitBody, validate } from "@luma/worker-kit/middleware";
import { FILE_NAME, missingRequest } from "@luma/contracts/backend/files";
import type { AppEnv } from "../../env";
import { ApiError } from "../../lib/errors";
import { uploadSize } from "../../lib/storage";
import { featureGuard } from "../../middleware/guard";
import { getFile, missingFiles, putFile } from "./service";

const fileName = (name: string) => {
  if (!FILE_NAME.test(name)) throw new ApiError(400, "BAD_REQUEST", "Invalid file name");
  return name;
};

export const files = new Hono<AppEnv>()
  .use(...featureGuard("BACKUP_ENABLED"))
  .post(
    "/missing",
    limitBody(256 * 1024),
    validate("json", missingRequest, 'Body must be {"names": string[≤1000]}'),
    async (c) =>
      c.json({
        missing: await missingFiles(c.env.BUCKET, c.get("user").id, c.req.valid("json").names),
      }),
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
