import { describe, expect, it } from "vitest";
import { sessionResponse } from "@luma/contracts/dashboard/auth";
import { inviteListResponse } from "@luma/contracts/dashboard/invites";
import { overviewResponse } from "@luma/contracts/dashboard/overview";
import { userDetailResponse, userListResponse } from "@luma/contracts/dashboard/users";
import {
  admin,
  invites,
  invitesPage,
  overview,
  user,
  userDetail,
  usersPage,
} from "../helpers/fixtures";

// The msw fixtures stand in for the worker: they must keep the contract's shape, or client tests
// pass against responses the worker never sends.
describe("client fixtures match the dashboard contract", () => {
  it.each([
    ["session", sessionResponse, admin],
    ["overview", overviewResponse, overview],
    ["user detail", userDetailResponse, userDetail()],
    ["users page", userListResponse, usersPage([user(1), user(2, { last_active_at: null })])],
    [
      "invites page",
      inviteListResponse,
      invitesPage(invites.items, new URL("http://localhost/api/invites")),
    ],
  ] as const)("%s", (_, schema, fixture) => {
    expect(schema.safeParse(fixture).error).toBeUndefined();
  });
});
