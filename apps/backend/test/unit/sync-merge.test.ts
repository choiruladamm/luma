import { describe, expect, it } from "vitest";
import { merge, type SyncRecord } from "../../src/features/sync/merge";

const rec = (over: Partial<SyncRecord> = {}): SyncRecord => ({
  kind: "reading_progress",
  key: "k",
  data: { paragraphIndex: 1 },
  updatedAt: 1000,
  deleted: false,
  schemaVersion: 18,
  ...over,
});

describe("merge", () => {
  it("takes a record the server has never seen", () => {
    const r = rec();
    expect(merge(undefined, r)).toBe(r);
  });

  it("newest wins by default, and an identical record writes nothing", () => {
    const old = rec();
    const newer = rec({ updatedAt: 2000, data: { paragraphIndex: 9 } });
    expect(merge(old, newer)).toEqual(newer);
    expect(merge(newer, old)).toBeNull();
    expect(merge(old, rec())).toBeNull();
  });

  it("never lets an older app overwrite a record from a newer schema", () => {
    const stored = rec({ schemaVersion: 19 });
    expect(merge(stored, rec({ updatedAt: 9999, schemaVersion: 18 }))).toBeNull();
    expect(merge(rec({ schemaVersion: 18 }), rec({ updatedAt: 2000, schemaVersion: 19 }))).not.toBeNull();
  });

  it("books: newest metadata, earliest firstOpened/finished, largest readingSeconds", () => {
    const a = rec({
      kind: "book",
      updatedAt: 1000,
      data: { title: "Old", firstOpenedAt: "2026-01-01T00:00:00.000Z", finishedAt: null, readingSeconds: 900 },
    });
    const b = rec({
      kind: "book",
      updatedAt: 2000,
      data: {
        title: "New",
        firstOpenedAt: "2026-02-01T00:00:00.000Z",
        finishedAt: "2026-03-01T00:00:00.000Z",
        readingSeconds: 100,
      },
    });
    const expected = {
      title: "New",
      firstOpenedAt: "2026-01-01T00:00:00.000Z",
      finishedAt: "2026-03-01T00:00:00.000Z",
      readingSeconds: 900,
    };
    expect(merge(a, b)?.data).toEqual(expected);
    // Pesan kalah tetap nyumbang field yang lebih awal/besar.
    expect(merge(b, a)?.data).toEqual(expected);
  });

  it("books: a newer tombstone deletes, an older one loses", () => {
    const live = rec({ kind: "book", updatedAt: 2000, data: { title: "x" } });
    const tomb = (t: number) => rec({ kind: "book", updatedAt: t, deleted: true, data: null });
    expect(merge(live, tomb(3000))).toEqual(tomb(3000));
    expect(merge(live, tomb(1000))).toBeNull();
    // Import ulang setelah dihapus menghidupkan lagi.
    expect(merge(tomb(3000), rec({ kind: "book", updatedAt: 4000, data: { title: "x" } }))?.deleted).toBe(false);
  });

  it("reading sessions are append-only", () => {
    const s = rec({ kind: "reading_session", data: { seconds: 60 } });
    expect(merge(s, rec({ kind: "reading_session", updatedAt: 5000, data: { seconds: 1 } }))).toBeNull();
  });

  it.each(["ai_result", "ai_breakdown"] as const)("%s: higher promptVersion, then newer createdAt", (kind) => {
    const ai = (promptVersion: number, createdAt: string, updatedAt: number) =>
      rec({ kind, updatedAt, data: { promptVersion, createdAt } });
    const v3 = ai(3, "2026-01-01T00:00:00.000Z", 1000);
    expect(merge(v3, ai(2, "2026-05-01T00:00:00.000Z", 9000))).toBeNull();
    expect(merge(v3, ai(4, "2025-01-01T00:00:00.000Z", 500))?.data?.promptVersion).toBe(4);
    expect(merge(v3, ai(3, "2026-02-01T00:00:00.000Z", 500))?.data?.createdAt).toBe("2026-02-01T00:00:00.000Z");
    expect(merge(v3, ai(3, "2025-12-01T00:00:00.000Z", 9000))).toBeNull();
    // Tombstone ai jatuh ke aturan waktu.
    expect(merge(v3, rec({ kind, updatedAt: 2000, deleted: true, data: null }))?.deleted).toBe(true);
  });
});
