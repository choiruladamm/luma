import { describe, expect, it } from "vitest";
import { dashboardErrorCode } from "../src/errors";
import { sessionResponse } from "../src/dashboard/auth";
import {
  inviteCodeParam,
  inviteCreateRequest,
  inviteCreateResponse,
  inviteListQuery,
  inviteListResponse,
} from "../src/dashboard/invites";
import { overviewResponse } from "../src/dashboard/overview";
import {
  banResponse,
  unbanResponse,
  userDetailResponse,
  userIdParam,
  userListQuery,
  userListResponse,
} from "../src/dashboard/users";

const iso = "2026-01-01T00:00:00.000Z";
const user = {
  id: "u1",
  email: "a@luma.test",
  name: "A",
  createdAt: iso,
  lastActiveAt: null,
  banned: false,
  hasAiKey: true,
  r2Bytes: 1,
  syncBytes: 2,
};

describe("dashboard contracts", () => {
  it("lists the codes the dashboard emits", () => {
    expect(dashboardErrorCode.options).toContain("OPENROUTER_FAILED");
  });

  it("applies the query defaults and bounds", () => {
    expect(userListQuery.parse({})).toEqual({ dir: "desc", page: 1, limit: 50 });
    expect(userListQuery.parse({ page: "2", q: " x " })).toMatchObject({ page: 2, q: "x" });
    expect(userListQuery.safeParse({ sort: "nope" }).success).toBe(false);
    expect(inviteListQuery.parse({})).toEqual({ sort: "default", dir: "desc", page: 1, limit: 20 });
    expect(inviteListQuery.safeParse({ limit: "500" }).success).toBe(false);
  });

  it("keeps the param and body messages", () => {
    expect(userIdParam.safeParse({ id: "bad id" }).error?.issues[0]?.message).toBe(
      "Invalid user id",
    );
    expect(inviteCodeParam.safeParse({ code: "x" }).error?.issues[0]?.message).toBe(
      "Invalid invite code",
    );
    expect(inviteCreateRequest.safeParse({ count: 0 }).success).toBe(false);
    expect(inviteCreateRequest.safeParse({ count: 1, extra: 1 }).success).toBe(false);
  });

  it("parses the response shapes", () => {
    const detail = {
      ...user,
      sessions: [{ userAgent: null, ipAddress: null, createdAt: iso, updatedAt: iso }],
      ai: { limit: 0.02, usageDaily: null, expiresAt: iso },
      invite: { code: "LUMA-AAAAA-BBBBB", usedAt: null },
      providers: ["google"],
    };
    expect(userListResponse.parse({ items: [user], total: 1, page: 1, pageCount: 1 })).toBeTruthy();
    expect(userDetailResponse.parse(detail)).toEqual(detail);
    expect(banResponse.parse({ banned: true, keyRevoked: false })).toBeTruthy();
    expect(unbanResponse.parse({ banned: false })).toBeTruthy();
    expect(
      inviteListResponse.parse({
        items: [{ code: "C", createdAt: null, usedBy: { id: "u", email: "e" }, usedAt: iso }],
        total: 1,
        page: 1,
        pageCount: 1,
        counts: { all: 1, unused: 0, used: 1 },
      }),
    ).toBeTruthy();
    expect(inviteCreateResponse.parse({ codes: ["C"], createdAt: iso })).toBeTruthy();
    expect(
      overviewResponse.parse({
        users: { total: 1, new7d: 0, banned: 0 },
        storage: { r2Bytes: 0, syncBytes: 0 },
        syncToday: { rows: 0, limit: 1 },
        invites: { unused: 0 },
        flags: { sync: true, backup: true, aiKey: false },
        ai: { spendUsd: null, budgetUsd: 5, asOf: "2026-11-19" },
      }),
    ).toBeTruthy();
    expect(sessionResponse.parse(null)).toBeNull();
    expect(
      sessionResponse.parse({
        user: { id: "u", email: "e", name: "n", image: null },
        session: { expiresAt: iso },
      }),
    ).toBeTruthy();
  });
});
