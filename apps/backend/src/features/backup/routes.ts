import { Hono } from "hono";
import { createDb } from "../../db/client";
import type { AppEnv } from "../../env";
import { backupGuard } from "../files/routes";
import { uploadSize } from "../files/service";
import { getBackup, listBackups, parseManifest, putBackup } from "./service";

export const backups = new Hono<AppEnv>()
  .use(...backupGuard)
  .put("/", async (c) => {
    const size = uploadSize(c.req.header("content-length"));
    const metadata = parseManifest(c.req.header("x-backup-manifest"));
    const backup = await putBackup(
      createDb(c.env.DB),
      c.env.BUCKET,
      Number(c.env.USER_STORAGE_BYTES),
      c.get("user").id,
      { size, body: c.req.raw.body, metadata },
    );
    return c.json(backup);
  })
  .get("/", async (c) => c.json({ backups: await listBackups(c.env.BUCKET, c.get("user").id) }))
  .get("/:id", async (c) => {
    const object = await getBackup(c.env.BUCKET, c.get("user").id, c.req.param("id"));
    return c.body(object.body, 200, {
      "content-type": "application/zip",
      "content-length": String(object.size),
    });
  });
