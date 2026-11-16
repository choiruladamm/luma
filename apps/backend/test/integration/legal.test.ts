import { env, exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";

const get = async (path: string) => {
  const res = await exports.default.fetch(`https://luma.test${path}`);
  return { res, body: await res.text() };
};

describe("store-required pages", () => {
  it.each(["/privacy", "/account/delete"])("%s is public English HTML with a contact and links to both pages", async (path) => {
    const { res, body } = await get(path);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("text/html");
    expect(body).toContain('<html lang="en">');
    expect(env.CONTACT_EMAIL).toMatch(/@/);
    expect(body).toContain(`mailto:${env.CONTACT_EMAIL}`);
    expect(body).toContain('href="/privacy"');
    expect(body).toContain('href="/account/delete"');
    expect(body).toMatch(/Last updated \w+ \d+, \d{4}/);
  });

  it("the privacy policy names what is stored and who processes it", async () => {
    const { body } = await get("/privacy");
    for (const text of ["Cloud backup", "Sync data", "OpenRouter", "Google", "Cloudflare", "directly from your phone", "Delete your account"]) {
      expect(body).toContain(text);
    }
  });

  it("the deletion page has the in-app steps (app labels), what is deleted, and the email fallback", async () => {
    const { body } = await get("/account/delete");
    for (const text of ["Settings → Account", "Delete account forever", "All cloud backups", "within 30 days", "subject=Delete%20my%20Luma%20account"]) {
      expect(body).toContain(text);
    }
  });
});
