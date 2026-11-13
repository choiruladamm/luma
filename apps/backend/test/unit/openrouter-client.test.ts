import { HttpResponse, http } from "msw";
import { describe, expect, it } from "vitest";
import { OPENROUTER_API, OpenRouterError, openRouterAdmin } from "../../src/clients/openrouter";
import { fakeOpenRouter } from "../helpers/openrouter";
import { network } from "../setup";

describe("openRouterAdmin", () => {
  it("sends the management key and the spike-verified create body", async () => {
    let seen: { auth: string | null; body: unknown } | undefined;
    network.use(
      http.post(`${OPENROUTER_API}/keys`, async ({ request }) => {
        seen = { auth: request.headers.get("authorization"), body: await request.json() };
        return HttpResponse.json({ data: { hash: "h1" }, key: "sk-or-v1-x" }, { status: 201 });
      }),
    );
    const expiresAt = new Date("2026-12-12T00:00:00Z");

    const created = await openRouterAdmin("mgmt").createKey({
      name: "luma-u1",
      limitUsd: 0.02,
      expiresAt,
      workspaceId: "ws-1",
    });

    expect(created).toEqual({ key: "sk-or-v1-x", hash: "h1" });
    expect(seen).toEqual({
      auth: "Bearer mgmt",
      body: {
        name: "luma-u1",
        limit: 0.02,
        limit_reset: "daily",
        include_byok_in_limit: true,
        expires_at: "2026-12-12T00:00:00.000Z",
        workspace_id: "ws-1",
      },
    });
  });

  it("updates limits and reads usage", async () => {
    const or = fakeOpenRouter();
    const admin = openRouterAdmin("mgmt");
    const { hash } = await admin.createKey({
      name: "n",
      limitUsd: 0.02,
      expiresAt: new Date(),
      workspaceId: "ws",
    });
    await admin.updateLimit(hash, 0.5);
    or.keys.get(hash)!.usageDaily = 0.1;

    expect(await admin.getUsage(hash)).toEqual({ limit: 0.5, limitRemaining: 0.4, usageDaily: 0.1 });
  });

  it("treats deleting a missing key as done, but surfaces other errors", async () => {
    fakeOpenRouter();
    const admin = openRouterAdmin("mgmt");
    await expect(admin.deleteKey("tidak-ada")).resolves.toBeUndefined();

    network.use(http.delete(`${OPENROUTER_API}/keys/:hash`, () => new HttpResponse(null, { status: 500 })));
    await expect(admin.deleteKey("x")).rejects.toBeInstanceOf(OpenRouterError);
  });

  it("throws OpenRouterError with the status on failures", async () => {
    network.use(http.post(`${OPENROUTER_API}/keys`, () => HttpResponse.json({}, { status: 401 })));
    await expect(
      openRouterAdmin("salah").createKey({ name: "n", limitUsd: 1, expiresAt: new Date(), workspaceId: "w" }),
    ).rejects.toMatchObject({ status: 401 });
  });
});
