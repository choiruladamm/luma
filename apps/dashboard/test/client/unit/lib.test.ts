import { describe, expect, it } from "vitest";
import { id } from "../../../client/i18n/id";
import {
  ApiError,
  errorText,
  toApiError,
  unwrap,
  unwrapEmpty,
} from "../../../client/lib/api-error";
import { isDevHost } from "../../../client/lib/env";
import { cn } from "../../../client/lib/cn";
import { formatBytes, formatRelative, formatUsd } from "../../../client/lib/format";

describe("client api-error", () => {
  it("maps the worker error body to a code; the copy comes from the code", async () => {
    const err = await toApiError(
      Response.json({ error: { code: "INVITE_CODE_USED", message: "used" } }, { status: 409 }),
    );
    expect(err).toMatchObject({ status: 409, code: "INVITE_CODE_USED", serverMessage: "used" });
    expect(errorText(err, id)).toBe("Kode undangan sudah dipakai.");
    expect(errorText(new Error("boom"), id)).toBe("Ada yang salah di server.");
  });

  it("falls back to INTERNAL_ERROR for unknown codes and non-JSON bodies", async () => {
    expect(
      (await toApiError(Response.json({ error: { code: "WAT" } }, { status: 500 }))).code,
    ).toBe("INTERNAL_ERROR");
    expect((await toApiError(new Response("<html>", { status: 502 }))).code).toBe("INTERNAL_ERROR");
  });

  it("unwrap returns JSON, throws ApiError on failure and NETWORK when fetch rejects", async () => {
    expect(await unwrap(Promise.resolve(Response.json({ a: 1 })))).toEqual({ a: 1 });
    await expect(
      unwrap(Promise.resolve(Response.json({ error: { code: "FORBIDDEN" } }, { status: 403 }))),
    ).rejects.toMatchObject({
      code: "FORBIDDEN",
      status: 403,
    });
    await expect(unwrap(Promise.reject(new TypeError("offline")))).rejects.toBeInstanceOf(ApiError);
    await expect(unwrap(Promise.reject(new TypeError("offline")))).rejects.toMatchObject({
      code: "NETWORK",
    });
  });
});

describe("client env + format", () => {
  it("shows the DEV badge everywhere but the prod host", () => {
    expect(isDevHost("luma-admin.chrl.cloud")).toBe(false);
    expect(isDevHost("luma-admin-dev.chrl.cloud")).toBe(true);
    expect(isDevHost("localhost")).toBe(true);
  });

  it("formats bytes and small USD amounts", () => {
    expect(formatBytes(0, "id-ID")).toBe("0 B");
    expect(formatBytes(1536, "id-ID")).toBe("1,5 KB");
    expect(formatBytes(20409434, "id-ID")).toBe("19,5 MB");
    expect(formatUsd(0.00676, "id-ID")).toMatch(/0,0068/);
  });
});

describe("client format: relative time", () => {
  const now = Date.parse("2026-11-15T12:00:00Z");
  const ago = (ms: number) => new Date(now - ms).toISOString();
  it.each([
    [null, "Belum pernah"],
    [ago(20_000), "Baru aja"],
    [ago(5 * 60_000), "5 mnt lalu"],
    [ago(3 * 3_600_000), "3 jam lalu"],
    [ago(30 * 3_600_000), "Kemarin"],
    [ago(4 * 86_400_000), "4 hari lalu"],
    [ago(15 * 86_400_000), "2 minggu lalu"],
  ])("%s → %s", (iso, label) => {
    expect(formatRelative(iso, { t: id, locale: "id-ID" }, now)).toBe(label);
  });

  it("falls back to the date after a month", () => {
    expect(formatRelative(ago(60 * 86_400_000), { t: id, locale: "id-ID" }, now)).toMatch(/2026/);
  });
});

describe("client cn", () => {
  it("joins truthy class names", () => {
    expect(cn("a", false, null, undefined, "b")).toBe("a b");
  });
});

describe("client unwrapEmpty", () => {
  it("resolves on 204 and keeps the error code of a failed empty-body call", async () => {
    await expect(
      unwrapEmpty(Promise.resolve(new Response(null, { status: 204 }))),
    ).resolves.toBeUndefined();
    await expect(
      unwrapEmpty(
        Promise.resolve(Response.json({ error: { code: "INVITE_CODE_USED" } }, { status: 409 })),
      ),
    ).rejects.toMatchObject({ code: "INVITE_CODE_USED" });
  });
});
