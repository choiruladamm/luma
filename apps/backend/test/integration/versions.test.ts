import { exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import signUpV1 from "@luma/contracts/fixtures/v1/auth-sign-up-email.json";
import signUpV2 from "@luma/contracts/fixtures/v2/auth-sign-up-email.json";
import badRequestV1 from "@luma/contracts/fixtures/v1/error-sync-bad-request.json";
import badRequestV2 from "@luma/contracts/fixtures/v2/error-sync-bad-request.json";
import pullV1 from "@luma/contracts/fixtures/v1/sync-pull.json";
import pullV2 from "@luma/contracts/fixtures/v2/sync-pull.json";
import pushV1 from "@luma/contracts/fixtures/v1/sync-push.json";
import pushV2 from "@luma/contracts/fixtures/v2/sync-push.json";
import { createInvite, signUp } from "../helpers/auth";
import { expectContract } from "../helpers/contract";

/** Both API versions answer the same fixtures in their own spelling (docs/backend.md, API versions). */
const matrix = [
  { wire: "v1", signUp: signUpV1, badRequest: badRequestV1, pull: pullV1, push: pushV1 },
  { wire: "v2", signUp: signUpV2, badRequest: badRequestV2, pull: pullV2, push: pushV2 },
] as const;

const json = (path: string, body: string, headers: Record<string, string> = {}) =>
  new Request(`https://luma.test${path}`, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body,
  });

describe.each(matrix)("$wire", ({ wire, signUp: signUpFixture, badRequest, pull, push }) => {
  it("signs up (contract)", async () => {
    const code = await createInvite();
    // Storage is shared within the file, so each version signs up its own email.
    const own = JSON.parse(
      JSON.stringify(signUpFixture).replaceAll("@", `.${wire}@`),
    ) as typeof signUpFixture;
    const res = await exports.default.fetch(
      json(own.request.path, JSON.stringify(own.request.body), { "x-invite-code": code }),
    );
    await expectContract(res, own);
  });

  it("pushes and pulls the fixtures, with data untouched (contract)", async () => {
    const { token } = await signUp();
    const auth = { authorization: `Bearer ${token}` };
    const pushed = await exports.default.fetch(
      json(push.request.path, JSON.stringify(push.request.body), auth),
    );
    expect(pushed.status).toBe(200);
    const pulled = await exports.default.fetch(
      new Request(`https://luma.test${pull.request.path}`, { headers: auth }),
    );
    await expectContract(pulled, pull);
  });

  it("names the push body's fields as the version spells them (contract)", async () => {
    const { token } = await signUp();
    const res = await exports.default.fetch(
      json(badRequest.request.path, JSON.stringify(badRequest.request.body), {
        authorization: `Bearer ${token}`,
      }),
    );
    await expectContract(res, badRequest);
  });

  it("rejects a malformed JSON body with 400", async () => {
    const { token } = await signUp();
    const res = await exports.default.fetch(
      json(`/${wire}/sync/push`, "{nope", { authorization: `Bearer ${token}` }),
    );
    expect(res.status).toBe(400);
  });
});

describe("/v1 adapter", () => {
  // /v1 accepted camelCase only before the adapter existed; it must keep rejecting the rest.
  it.each([
    ["snake_case keys", pushV2.request.body],
    ["both spellings of one key", { ...pushV1.request.body, schema_version: 1 }],
  ])("rejects a push body with %s, as before", async (_, body) => {
    const { token } = await signUp();
    const res = await exports.default.fetch(
      json("/v1/sync/push", JSON.stringify(body), { authorization: `Bearer ${token}` }),
    );
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual(badRequestV1.response.body);
  });

  it("still converts keys inside records but never the records' data", async () => {
    const { token } = await signUp();
    const body = structuredClone(pushV1.request.body);
    body.records[0]!.data = { some_snake_key: 1, camelKey: 2 } as never;
    const res = await exports.default.fetch(
      json("/v1/sync/push", JSON.stringify(body), { authorization: `Bearer ${token}` }),
    );
    expect(res.status).toBe(200);
  });
});

describe("/v2/auth", () => {
  it("passes a malformed or empty body to Better Auth, which rejects it", async () => {
    const malformed = await exports.default.fetch(json("/v2/auth/sign-in/email", "{nope"));
    expect(malformed.status).toBeGreaterThanOrEqual(400);
    const empty = await exports.default.fetch(
      new Request("https://luma.test/v2/auth/sign-in/email", { method: "POST" }),
    );
    expect(empty.status).toBeGreaterThanOrEqual(400);
  });

  it("signs out without a JSON body", async () => {
    const { token } = await signUp();
    const res = await exports.default.fetch(
      new Request("https://luma.test/v2/auth/sign-out", {
        method: "POST",
        headers: { authorization: `Bearer ${token}` },
      }),
    );
    expect(res.status).toBeLessThan(500);
  });
});
