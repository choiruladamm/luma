import { env } from "cloudflare:test";
import { Hono } from "hono";
import { describe, expect, it } from "vitest";
import type { AppEnv } from "../../src/env";
import { onError } from "../../src/lib/errors";
import { JSON_BODY_LIMIT, limitBody } from "../../src/middleware/body-limit";
import { killSwitch } from "../../src/middleware/kill-switch";
import disabled from "../fixtures/contract/error-service-disabled.json";
import { countingD1 } from "../helpers/budget";

/** App mini dengan middleware yang dipasang per grup route di fitur nanti. */
function appWith(touchDb: () => void) {
  const app = new Hono<AppEnv>();
  app.use("/v1/sync/*", killSwitch("SYNC_ENABLED"), limitBody());
  app.post("/v1/sync/push", async (c) => {
    touchDb();
    await c.req.text();
    return c.json({ ok: true });
  });
  app.onError(onError);
  return app;
}

describe("killSwitch", () => {
  it("returns 503 + Retry-After without touching D1 when off (contract)", async () => {
    const d1 = countingD1(env.DB);
    const app = appWith(() => d1.db.prepare("SELECT 1"));
    const res = await app.request(
      disabled.request.path,
      { method: "POST", body: "{}" },
      { ...env, DB: d1.db, SYNC_ENABLED: "false" },
    );
    expect(res.status).toBe(disabled.response.status);
    expect(res.headers.get("Retry-After")).toBe(disabled.response.headers["Retry-After"]);
    expect(await res.json()).toEqual(disabled.response.body);
    expect(d1.count()).toBe(0);
  });

  it("treats anything but \"true\" as off", async () => {
    const app = appWith(() => {});
    const res = await app.request("/v1/sync/push", { method: "POST", body: "{}" }, {
      ...env,
      SYNC_ENABLED: "TRUE",
    });
    expect(res.status).toBe(503);
  });

  it("lets the request through when on", async () => {
    const app = appWith(() => {});
    const res = await app.request("/v1/sync/push", { method: "POST", body: "{}" }, env);
    expect(res.status).toBe(200);
  });
});

describe("limitBody", () => {
  it("rejects bodies over the limit with 413", async () => {
    const app = appWith(() => {});
    const res = await app.request(
      "/v1/sync/push",
      { method: "POST", body: "x".repeat(JSON_BODY_LIMIT + 1) },
      env,
    );
    expect(res.status).toBe(413);
    expect(await res.json()).toEqual({
      error: { code: "PAYLOAD_TOO_LARGE", message: `Body exceeds ${JSON_BODY_LIMIT} bytes` },
    });
  });

  it("accepts a body exactly at the limit", async () => {
    const app = appWith(() => {});
    const res = await app.request(
      "/v1/sync/push",
      { method: "POST", body: "x".repeat(JSON_BODY_LIMIT) },
      env,
    );
    expect(res.status).toBe(200);
  });
});
