import { describe, expect, it, vi } from "vitest";
import { audit } from "../../worker/lib/audit";
import { isAdmin } from "../../worker/auth/admin";

const user = (email: string, emailVerified = true) => ({ email, emailVerified });

describe("isAdmin", () => {
  it.each([
    ["", "a@x.com", false],
    [" , ", "a@x.com", false],
    ["a@x.com", "a@x.com", true],
    [" B@X.com ,a@x.com", "b@x.COM", true],
    ["ba@x.com", "a@x.com", false],
    ["a@x.com", "ba@x.com", false],
    ["a@x.com.evil", "a@x.com", false],
    ["a@x.com,b@x.com", "a@x.com,b@x.com", false],
  ])("ADMIN_EMAILS=%j email=%j → %s", (ADMIN_EMAILS, email, expected) => {
    expect(isAdmin({ ADMIN_EMAILS }, user(email))).toBe(expected);
  });

  it("requires emailVerified", () => {
    expect(isAdmin({ ADMIN_EMAILS: "a@x.com" }, user("a@x.com", false))).toBe(false);
  });
});

describe("audit", () => {
  it("logs {admin, action, targetId, requestId} as one JSON line", () => {
    const log = vi.spyOn(console, "log").mockImplementation(() => {});
    const c = { var: { admin: { id: "u1", email: "admin@x.com" }, requestId: "req-1" } };
    audit(c as never, "user.ban", "u2");
    expect(JSON.parse(log.mock.calls[0]![0] as string)).toEqual({
      message: "audit",
      admin: "admin@x.com",
      action: "user.ban",
      targetId: "u2",
      requestId: "req-1",
    });
    log.mockRestore();
  });
});
