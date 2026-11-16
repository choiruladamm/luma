import { env } from "cloudflare:test";
import { exports } from "cloudflare:workers";
import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { createDb } from "../../src/db/client";
import { userStorage } from "../../src/db/schema";
import backupsList from "../fixtures/contract/backups-list.json";
import backupsPut from "../fixtures/contract/backups-put.json";
import notFound from "../fixtures/contract/error-backup-not-found.json";
import storageFull from "../fixtures/contract/error-storage-full.json";
import unauthorized from "../fixtures/contract/error-unauthorized.json";
import filesMissing from "../fixtures/contract/files-missing.json";
import filesPut from "../fixtures/contract/files-put.json";
import { signUp } from "../helpers/auth";
import { callWithBudget } from "../helpers/budget";
import { expectContract } from "../helpers/contract";

const url = (path: string) => `https://luma.test${path}`;
const auth = (token: string) => ({ authorization: `Bearer ${token}` });
const manifest = backupsPut.request.headers["x-backup-manifest"];

const putFile = (token: string, name: string, body: string) =>
  new Request(url(`/v1/files/${name}`), {
    method: "PUT",
    headers: { ...auth(token), "content-length": String(body.length) },
    body,
  });
const missing = (token: string, names: string[]) =>
  new Request(url("/v1/files/missing"), {
    method: "POST",
    headers: { ...auth(token), "content-type": "application/json" },
    body: JSON.stringify({ names }),
  });
const putBackup = (token: string, body = "zipbytes") =>
  new Request(url("/v1/backups"), {
    method: "PUT",
    headers: { ...auth(token), "content-length": String(body.length), "x-backup-manifest": manifest },
    body,
  });
const get = (token: string, path: string) => new Request(url(path), { headers: auth(token) });
const bytes = async (userId: string) =>
  (await createDb(env.DB).select().from(userStorage).where(eq(userStorage.userId, userId)))[0]?.bytes ?? 0;

describe("files", () => {
  it("reports which names are not in R2 yet, then stores them (contract)", async () => {
    const { token, userId } = await signUp();
    await exports.default.fetch(putFile(token, "3539482a.epub", "epub!"));

    await expectContract(await exports.default.fetch(missing(token, filesMissing.request.body.names)), filesMissing);
    await expectContract(await exports.default.fetch(putFile(token, "3539482a.jpg", filesPut.request.body)), filesPut);

    const after = (await (await exports.default.fetch(missing(token, filesMissing.request.body.names))).json()) as {
      missing: string[];
    };
    expect(after.missing).toEqual([]);
    expect(await bytes(userId)).toBe(10);
  });

  it("downloads a stored file and skips re-uploads without counting twice", async () => {
    const { token, userId } = await signUp();
    await exports.default.fetch(putFile(token, "a.epub", "hello"));
    const again = await exports.default.fetch(putFile(token, "a.epub", "hello"));
    expect(again.status).toBe(200);
    expect(await bytes(userId)).toBe(5);

    const res = await exports.default.fetch(get(token, "/v1/files/a.epub"));
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("hello");
    expect((await exports.default.fetch(get(token, "/v1/files/none.epub"))).status).toBe(404);
  });

  it("rejects bad names, missing Content-Length, lying lengths and bad bodies", async () => {
    const { token } = await signUp();
    expect((await exports.default.fetch(putFile(token, "..%2Fx", "x"))).status).toBe(400);
    expect((await exports.default.fetch(missing(token, ["../x"]))).status).toBe(400);
    expect((await exports.default.fetch(missing(token, Array(1001).fill("a")))).status).toBe(400);
    const noLength = new Request(url("/v1/files/a.epub"), { method: "PUT", headers: auth(token) });
    expect((await exports.default.fetch(noLength)).status).toBe(400);
    const lying = new Request(url("/v1/files/b.epub"), {
      method: "PUT",
      headers: { ...auth(token), "content-length": "3" },
      body: new Blob(["hello"]).stream(),
    });
    expect((await exports.default.fetch(lying)).status).not.toBe(200);
    expect((await exports.default.fetch(get(token, "/v1/files/b.epub"))).status).toBe(404);
  });

  it("refuses uploads over the user's quota (contract)", async () => {
    const { token, userId } = await signUp();
    await createDb(env.DB).insert(userStorage).values({ userId, bytes: Number(env.USER_STORAGE_BYTES) });
    await expectContract(await exports.default.fetch(putFile(token, "big.epub", "x")), storageFull);
    const tooBig = new Request(url("/v1/files/big.epub"), {
      method: "PUT",
      headers: { ...auth(token), "content-length": String(101 * 1024 * 1024) },
    });
    expect((await exports.default.fetch(tooBig)).status).toBe(413);
  });

  it("keeps each user's files to themselves", async () => {
    const a = await signUp();
    const b = await signUp();
    await exports.default.fetch(putFile(a.token, "secret.epub", "aaaaa"));

    expect((await exports.default.fetch(get(b.token, "/v1/files/secret.epub"))).status).toBe(404);
    const res = (await (await exports.default.fetch(missing(b.token, ["secret.epub"]))).json()) as { missing: string[] };
    expect(res.missing).toEqual(["secret.epub"]);
  });

  it("stays inside the budget: missing = 1 list, upload = 1 head + 1 put", async () => {
    const { token } = await signUp();
    const m = await callWithBudget(missing(token, ["a.epub"]));
    expect(m.response.status).toBe(200);
    expect(m.subrequests).toBe(0);
    expect(m.d1Queries).toBeLessThanOrEqual(1);

    const up = await callWithBudget(putFile(token, "a.epub", "hello"));
    expect(up.response.status).toBe(200);
    expect(up.subrequests).toBe(0);
    expect(up.d1Queries).toBeLessThanOrEqual(3);
  });
});

describe("backups", () => {
  it("stores a snapshot with its manifest and lists it (contract)", async () => {
    const { token, userId } = await signUp();
    const put = (await expectContract(await exports.default.fetch(putBackup(token)), backupsPut)) as { id: string };
    expect(put.id).toMatch(/^\d{8}T\d{6}Z$/);

    const list = (await expectContract(await exports.default.fetch(get(token, "/v1/backups")), backupsList)) as {
      backups: { id: string }[];
    };
    expect(list.backups[0]!.id).toBe(put.id);

    const zip = await exports.default.fetch(get(token, `/v1/backups/${put.id}`));
    expect(zip.status).toBe(200);
    expect(zip.headers.get("content-type")).toBe("application/zip");
    expect(await zip.text()).toBe("zipbytes");
    expect(await bytes(userId)).toBe(8);
  });

  it("keeps only the newest 10 snapshots and frees their bytes", async () => {
    const { token, userId } = await signUp();
    const prefix = `u/${userId}/backups/`;
    for (let i = 0; i < 11; i++) {
      await env.BUCKET.put(`${prefix}202601${String(i + 1).padStart(2, "0")}T000000Z.zip`, "old");
    }
    await createDb(env.DB).insert(userStorage).values({ userId, bytes: 33 });

    expect((await exports.default.fetch(putBackup(token))).status).toBe(200);

    const listed = await env.BUCKET.list({ prefix });
    expect(listed.objects).toHaveLength(10);
    expect(await bytes(userId)).toBe(33 + 8 - 2 * 3);
  });

  it("404s an unknown or malformed snapshot id (contract)", async () => {
    const { token } = await signUp();
    await expectContract(await exports.default.fetch(get(token, notFound.request.path)), notFound);
    expect((await exports.default.fetch(get(token, "/v1/backups/..%2F..%2Fx"))).status).toBe(404);
  });

  it("rejects a missing manifest or length, and a full quota", async () => {
    const { token, userId } = await signUp();
    const noManifest = new Request(url("/v1/backups"), {
      method: "PUT",
      headers: { ...auth(token), "content-length": "3" },
      body: "zip",
    });
    expect((await exports.default.fetch(noManifest)).status).toBe(400);
    const noLength = new Request(url("/v1/backups"), {
      method: "PUT",
      headers: { ...auth(token), "x-backup-manifest": manifest },
    });
    expect((await exports.default.fetch(noLength)).status).toBe(400);

    await createDb(env.DB).insert(userStorage).values({ userId, bytes: Number(env.USER_STORAGE_BYTES) });
    expect((await exports.default.fetch(putBackup(token))).status).toBe(413);
  });

  it("never shows one user's snapshots to another", async () => {
    const a = await signUp();
    const b = await signUp();
    const { id } = (await (await exports.default.fetch(putBackup(a.token))).json()) as { id: string };

    const list = (await (await exports.default.fetch(get(b.token, "/v1/backups"))).json()) as { backups: unknown[] };
    expect(list.backups).toEqual([]);
    expect((await exports.default.fetch(get(b.token, `/v1/backups/${id}`))).status).toBe(404);
  });

  it("stays inside the budget: put = 1 put + 1 list (+1 delete), 2 D1 queries", async () => {
    const { token } = await signUp();
    const put = await callWithBudget(putBackup(token));
    expect(put.response.status).toBe(200);
    expect(put.subrequests).toBe(0);
    expect(put.d1Queries).toBeLessThanOrEqual(3);
  });
});

describe("guards", () => {
  it.each([
    ["POST", "/v1/files/missing"],
    ["PUT", "/v1/files/a.epub"],
    ["GET", "/v1/files/a.epub"],
    ["PUT", "/v1/backups"],
    ["GET", "/v1/backups"],
    ["GET", "/v1/backups/20261113T100405Z"],
  ])("%s %s needs a session (contract)", async (method, path) => {
    await expectContract(await exports.default.fetch(url(path), { method }), unauthorized);
  });

  it("answers 503 without touching D1 or R2 when backup is switched off", async () => {
    const { token } = await signUp();
    let touched = false;
    const bucket = new Proxy(env.BUCKET, {
      get: () => () => {
        touched = true;
      },
    });
    const { response, d1Queries } = await callWithBudget(putBackup(token), {
      BACKUP_ENABLED: "false",
      BUCKET: bucket,
    });
    expect(response.status).toBe(503);
    expect(d1Queries).toBe(0);
    expect(touched).toBe(false);
  });

  it("is rate limited per user", async () => {
    const { token } = await signUp();
    const deny = { limit: async () => ({ success: false }) } as unknown as RateLimit;
    const { response } = await callWithBudget(get(token, "/v1/backups"), { RATE_LIMITER: deny });
    expect(response.status).toBe(429);
  });
});
