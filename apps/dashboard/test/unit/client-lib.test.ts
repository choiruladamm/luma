import { describe, expect, it } from "vitest";
import { ApiError, toApiError, unwrap } from "../../client/lib/api-error";
import { isDevHost } from "../../client/lib/env";
import { formatBytes, formatUsd } from "../../client/lib/format";

describe("client api-error", () => {
  it("maps the worker error body to a code with Indonesian copy", async () => {
    const err = await toApiError(Response.json({ error: { code: "INVITE_CODE_USED", message: "used" } }, { status: 409 }));
    expect(err).toMatchObject({ status: 409, code: "INVITE_CODE_USED", serverMessage: "used" });
    expect(err.message).toBe("Kode undangan sudah dipakai.");
  });

  it("falls back to INTERNAL_ERROR for unknown codes and non-JSON bodies", async () => {
    expect((await toApiError(Response.json({ error: { code: "WAT" } }, { status: 500 }))).code).toBe("INTERNAL_ERROR");
    expect((await toApiError(new Response("<html>", { status: 502 }))).code).toBe("INTERNAL_ERROR");
  });

  it("unwrap returns JSON, throws ApiError on failure and NETWORK when fetch rejects", async () => {
    expect(await unwrap(Promise.resolve(Response.json({ a: 1 })))).toEqual({ a: 1 });
    await expect(unwrap(Promise.resolve(Response.json({ error: { code: "FORBIDDEN" } }, { status: 403 })))).rejects.toMatchObject({
      code: "FORBIDDEN",
      status: 403,
    });
    await expect(unwrap(Promise.reject(new TypeError("offline")))).rejects.toBeInstanceOf(ApiError);
    await expect(unwrap(Promise.reject(new TypeError("offline")))).rejects.toMatchObject({ code: "NETWORK" });
  });
});

describe("client env + format", () => {
  it("shows the DEV badge everywhere but the prod host", () => {
    expect(isDevHost("luma-admin.chrl.cloud")).toBe(false);
    expect(isDevHost("luma-admin-dev.chrl.cloud")).toBe(true);
    expect(isDevHost("localhost")).toBe(true);
  });

  it("formats bytes and small USD amounts", () => {
    expect(formatBytes(0)).toBe("0 B");
    expect(formatBytes(1536)).toBe("1,5 KB");
    expect(formatBytes(20409434)).toBe("19,5 MB");
    expect(formatUsd(0.00676)).toMatch(/0,0068/);
  });
});
