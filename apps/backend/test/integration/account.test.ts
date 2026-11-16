import { env } from "cloudflare:test";
import { exports } from "cloudflare:workers";
import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { createDb } from "../../src/db/client";
import { users } from "../../src/db/schema";
import { userPrefix } from "../../src/lib/storage";
import meDelete from "../fixtures/contract/me-delete.json";
import me from "../fixtures/contract/me.json";
import unauthorized from "../fixtures/contract/error-unauthorized.json";
import { signUp } from "../helpers/auth";
import { callWithBudget } from "../helpers/budget";
import { expectContract } from "../helpers/contract";

const url = (path: string) => `https://luma.test${path}`;
const auth = (token: string) => ({ authorization: `Bearer ${token}` });

describe("GET /v1/me", () => {
  it("returns the signed-in user (contract)", async () => {
    const { token } = await signUp("adam@luma.test");
    const res = await exports.default.fetch(url("/v1/me"), { headers: auth(token) });
    const body = (await expectContract(res, {
      response: { ...me.response, body: { user: { ...me.response.body.user, name: "Tester" } } },
    })) as { user: { email: string } };
    expect(body.user.email).toBe("adam@luma.test");
  });

  it("answers 401 without a token or with a bad one (contract)", async () => {
    await expectContract(await exports.default.fetch(url("/v1/me")), unauthorized);
    await expectContract(
      await exports.default.fetch(url("/v1/me"), { headers: auth("bukan-token") }),
      unauthorized,
    );
  });

  it("only ever returns the caller (user isolation)", async () => {
    const a = await signUp();
    const b = await signUp();
    const resA = await exports.default.fetch(url("/v1/me"), { headers: auth(a.token) });
    const resB = await exports.default.fetch(url("/v1/me"), { headers: auth(b.token) });
    expect(((await resA.json()) as { user: { id: string } }).user.id).toBe(a.userId);
    expect(((await resB.json()) as { user: { id: string } }).user.id).toBe(b.userId);
  });

  it("stays inside the budget: session lookup only, no subrequest", async () => {
    const { token } = await signUp();
    const { response, d1Queries, subrequests } = await callWithBudget(
      new Request(url("/v1/me"), { headers: auth(token) }),
    );
    expect(response.status).toBe(200);
    expect(d1Queries).toBeLessThanOrEqual(2);
    expect(subrequests).toBe(0);
  });
});

describe("DELETE /v1/me", () => {
  it("deletes the user's R2 objects and account, leaves others alone (contract)", async () => {
    const a = await signUp();
    const b = await signUp();
    await env.BUCKET.put(`${userPrefix(a.userId)}files/one.epub`, "a1");
    await env.BUCKET.put(`${userPrefix(a.userId)}backups/1.zip`, "a2");
    await env.BUCKET.put(`${userPrefix(b.userId)}files/two.epub`, "b1");

    const res = await exports.default.fetch(url(meDelete.request.path), {
      method: "DELETE",
      headers: auth(a.token),
    });
    await expectContract(res, meDelete);

    expect((await env.BUCKET.list({ prefix: userPrefix(a.userId) })).objects).toHaveLength(0);
    expect((await env.BUCKET.list({ prefix: userPrefix(b.userId) })).objects).toHaveLength(1);
    const rows = await createDb(env.DB).select().from(users).where(eq(users.id, a.userId));
    expect(rows).toHaveLength(0);

    const after = await exports.default.fetch(url("/v1/me"), { headers: auth(a.token) });
    expect(after.status).toBe(401);
    const other = await exports.default.fetch(url("/v1/me"), { headers: auth(b.token) });
    expect(other.status).toBe(200);
  });

  it("requires a session", async () => {
    const res = await exports.default.fetch(url("/v1/me"), { method: "DELETE" });
    expect(res.status).toBe(401);
  });
});
