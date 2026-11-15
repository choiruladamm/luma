import { describe, expect, it } from "vitest";
import { en } from "../../../client/i18n/en";
import { id } from "../../../client/i18n/id";
import { chooseLang, getI18n, resolveLang } from "../../../client/i18n";
import { formatBytes, formatDate, formatRelative, formatUsd } from "../../../client/lib/format";
import { useUiStore } from "../../../client/stores/ui-store";

/** Every leaf path with its kind: a string, or a function of N parameters. */
function shape(obj: object, prefix = ""): string[] {
  return Object.entries(obj).flatMap(([k, v]) =>
    typeof v === "object" ? shape(v as object, `${prefix}${k}.`) : [`${prefix}${k}:${typeof v === "function" ? `fn${(v as () => string).length}` : typeof v}`],
  );
}

describe("i18n messages", () => {
  // tsc already checks en against Messages; this also catches a parameter dropped from a function.
  it("en has exactly the keys and parameters of id", () => {
    expect(shape(en).sort()).toEqual(shape(id).sort());
  });

  it("no empty copy", () => {
    const leaves = (o: object): unknown[] => Object.values(o).flatMap((v) => (typeof v === "object" ? leaves(v as object) : [v]));
    for (const v of [...leaves(id), ...leaves(en)]) if (typeof v === "string") expect(v.trim()).not.toBe("");
  });

  it("pluralizes English, Indonesian has one form", () => {
    expect([en.time.minutes(1), en.time.minutes(2), en.time.weeks(1), en.time.days(3)]).toEqual(["1 min ago", "2 mins ago", "1 week ago", "3 days ago"]);
    expect([id.time.minutes(1), id.time.minutes(2)]).toEqual(["1 mnt lalu", "2 mnt lalu"]);
  });
});

describe("resolveLang", () => {
  it.each([
    [null, "en-US", "en"],
    [null, "en-GB", "en"],
    [null, "id-ID", "id"],
    [null, "ja", "id"],
    ["id", "en-US", "id"],
    ["en", "id-ID", "en"],
  ] as const)("saved %s, browser %s → %s", (saved, browser, lang) => {
    expect(resolveLang(saved, browser)).toBe(lang);
  });
});

describe("chooseLang", () => {
  it("loads English, then switches and saves the choice", async () => {
    await chooseLang("en");
    expect(getI18n()).toMatchObject({ lang: "en", locale: "en" });
    expect(getI18n().t.shell.signOut).toBe("Sign out");
    expect(JSON.parse(localStorage.getItem("luma-admin-ui")!).state.lang).toBe("en");
  });
});

describe("format in English", () => {
  const i18n = { t: en, locale: "en" };
  it("uses English separators, dates, and relative copy", () => {
    expect(formatBytes(1536, "en")).toBe("1.5 KB");
    expect(formatUsd(0.00676, "en")).toBe("$0.0068");
    expect(formatDate("2026-11-14T12:00:00Z", "en")).toBe("Nov 14, 2026");
    const now = Date.parse("2026-11-15T12:00:00Z");
    expect(formatRelative(null, i18n, now)).toBe("Never");
    expect(formatRelative(new Date(now - 30 * 3_600_000).toISOString(), i18n, now)).toBe("Yesterday");
  });
});
