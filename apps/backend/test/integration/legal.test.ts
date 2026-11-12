import { exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";

describe("store-required pages", () => {
  it.each(["/privacy", "/account/delete"])("%s is public HTML with a contact", async (path) => {
    const res = await exports.default.fetch(`https://luma.test${path}`);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("text/html");
    expect(await res.text()).toContain("work.adamm@gmail.com");
  });
});
