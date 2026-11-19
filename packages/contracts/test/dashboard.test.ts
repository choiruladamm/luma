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
  created_at: iso,
  last_active_at: null,
  banned: false,
  has_ai_key: true,
  r2_bytes: 1,
  sync_bytes: 2,
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
      sessions: [{ user_agent: null, ip_address: null, created_at: iso, updated_at: iso }],
      ai: { limit: 0.02, usage_daily: null, expires_at: iso },
      invite: { code: "LUMA-AAAAA-BBBBB", used_at: null },
      providers: ["google"],
    };
    expect(
      userListResponse.parse({ items: [user], total: 1, page: 1, page_count: 1 }),
    ).toBeTruthy();
    expect(userDetailResponse.parse(detail)).toEqual(detail);
    expect(banResponse.parse({ banned: true, key_revoked: false })).toBeTruthy();
    expect(unbanResponse.parse({ banned: false })).toBeTruthy();
    expect(
      inviteListResponse.parse({
        items: [{ code: "C", created_at: null, used_by: { id: "u", email: "e" }, used_at: iso }],
        total: 1,
        page: 1,
        page_count: 1,
        counts: { all: 1, unused: 0, used: 1 },
      }),
    ).toBeTruthy();
    expect(inviteCreateResponse.parse({ codes: ["C"], created_at: iso })).toBeTruthy();
    expect(
      overviewResponse.parse({
        users: { total: 1, new7d: 0, banned: 0 },
        storage: { r2_bytes: 0, sync_bytes: 0 },
        sync_today: { rows: 0, limit: 1 },
        invites: { unused: 0 },
        flags: { sync: true, backup: true, ai_key: false },
        ai: { spend_usd: null, budget_usd: 5, as_of: "2026-11-19" },
      }),
    ).toBeTruthy();
    expect(sessionResponse.parse(null)).toBeNull();
    expect(
      sessionResponse.parse({
        user: { id: "u", email: "e", name: "n", image: null },
        session: { expires_at: iso },
      }),
    ).toBeTruthy();
  });
});
