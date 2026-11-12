import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { countingD1 } from "../helpers/budget";

describe("countingD1", () => {
  it("counts every prepared statement and exec", async () => {
    const d1 = countingD1(env.DB);
    await d1.db.prepare("SELECT 1").first();
    await d1.db.batch([d1.db.prepare("SELECT 1"), d1.db.prepare("SELECT 2")]);
    await d1.db.exec("SELECT 3");
    expect(d1.count()).toBe(4);
  });
});
