import { describe, expect, it } from "vitest";
import { backupId, parseManifest, staleBackups } from "../../src/features/backup/service";
import { assertFits, MAX_UPLOAD_BYTES, uploadSize } from "../../src/features/files/service";
import backupsPut from "../fixtures/contract/backups-put.json";

describe("backupId", () => {
  it("is UTC yyyyMMddTHHmmssZ, so key order = time order", () => {
    expect(backupId(new Date("2026-11-13T10:04:05.678Z"))).toBe("20261113T100405Z");
    expect(backupId(new Date("2026-01-02T03:04:05Z")) < backupId(new Date("2026-11-13T00:00:00Z"))).toBe(true);
  });
});

describe("staleBackups", () => {
  it("keeps the newest 10 and drops the oldest", () => {
    const keys = Array.from({ length: 12 }, (_, i) => `k${String(i).padStart(2, "0")}`);
    expect(staleBackups(keys)).toEqual(["k00", "k01"]);
    expect(staleBackups(keys.slice(0, 10))).toEqual([]);
    expect(staleBackups([])).toEqual([]);
  });
});

describe("parseManifest", () => {
  it("turns the app manifest into R2 metadata with a UTC createdAt", () => {
    expect(parseManifest(backupsPut.request.headers["x-backup-manifest"])).toEqual({
      appVersion: "0.3.0",
      schemaVersion: "17",
      createdAt: "2026-11-13T10:04:05.000Z",
      books: "12",
      aiResults: "185",
    });
  });

  it.each([undefined, "", "nope", "{}", '{"appVersion":"1","schemaVersion":1,"createdAt":"kemarin","counts":{"books":0,"aiResults":0}}'])(
    "rejects %s",
    (header) => expect(() => parseManifest(header)).toThrow(/x-backup-manifest/),
  );
});

describe("uploadSize / assertFits", () => {
  it("needs a Content-Length within 100MB", () => {
    expect(uploadSize("0")).toBe(0);
    expect(uploadSize(String(MAX_UPLOAD_BYTES))).toBe(MAX_UPLOAD_BYTES);
    expect(() => uploadSize(undefined)).toThrow("Content-Length required");
    expect(() => uploadSize("-1")).toThrow("Content-Length required");
    expect(() => uploadSize("1.5")).toThrow("Content-Length required");
    expect(() => uploadSize(String(MAX_UPLOAD_BYTES + 1))).toThrow(/exceeds/);
  });

  it("allows filling the quota exactly, not past it", () => {
    expect(() => assertFits(90, 10, 100)).not.toThrow();
    expect(() => assertFits(90, 11, 100)).toThrow("Cloud storage is full");
  });
});
