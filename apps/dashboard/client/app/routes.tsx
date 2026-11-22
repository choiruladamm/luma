import type { RouteObject } from "react-router";
import { sessionQuery } from "../features/auth/queries/use-session";
import { parseInvitesParams } from "../features/invites/hooks/use-invites-params";
import { invitesQuery } from "../features/invites/queries/use-invites";
import { overviewQuery } from "../features/overview/queries/use-overview";
import { usageOverviewQuery } from "../features/overview/queries/use-usage-overview";
import { userDetailQuery } from "../features/users/queries/use-user-detail";
import { userUsageQuery } from "../features/users/queries/use-user-usage";
import { DEFAULT_USERS_PARAMS, parseUsersParams } from "../features/users/hooks/use-users-params";
import { usersQuery } from "../features/users/queries/use-users";
import { prefetch } from "./prefetch";
// Not lazy: they must render even when a screen's chunk fails to load.
import { AppError, NotFoundScreen, ScreenError } from "./route-error";

// Routing only: screens read their data through TanStack Query hooks. Every screen is its own
// chunk (lazy), so /login doesn't download the admin screens; each route's loader starts that
// screen's queries in parallel with the chunk download instead of after it renders.
// Shared by the browser router and the tests.
export const routes: RouteObject[] = [
  {
    path: "/login",
    ErrorBoundary: AppError,
    lazy: async () => ({
      Component: (await import("../features/auth/pages/login-page")).LoginPage,
    }),
  },
  {
    // The shell shows nav counts from the overview, so every admin screen warms it too.
    loader: prefetch(
      (qc) => qc.query(sessionQuery),
      (qc) => qc.query(overviewQuery),
    ),
    // Blank while the first loader + chunk settle, same as the guard's pending state.
    HydrateFallback: () => null,
    ErrorBoundary: AppError,
    lazy: async () => ({ Component: (await import("./require-session")).RequireSession }),
    children: [
      {
        index: true,
        ErrorBoundary: ScreenError,
        loader: prefetch(
          (qc) => qc.query(usersQuery(DEFAULT_USERS_PARAMS)),
          (qc) => qc.query(usageOverviewQuery),
        ),
        lazy: async () => ({
          Component: (await import("../features/overview/pages/overview-page")).OverviewPage,
        }),
      },
      {
        path: "users",
        ErrorBoundary: ScreenError,
        loader: prefetch((qc, { request }) =>
          qc.query(usersQuery(parseUsersParams(new URL(request.url).searchParams))),
        ),
        lazy: async () => ({
          Component: (await import("../features/users/pages/users-page")).UsersPage,
        }),
      },
      {
        path: "users/:id",
        ErrorBoundary: ScreenError,
        loader: prefetch(
          (qc, { params }) => qc.query(userDetailQuery(params.id ?? "")),
          (qc, { params }) => qc.query(userUsageQuery(params.id ?? "")),
        ),
        lazy: async () => ({
          Component: (await import("../features/users/pages/user-detail-page")).UserDetailPage,
        }),
      },
      {
        path: "invites",
        ErrorBoundary: ScreenError,
        loader: prefetch((qc, { request }) =>
          qc.query(invitesQuery(parseInvitesParams(new URL(request.url).searchParams))),
        ),
        lazy: async () => ({
          Component: (await import("../features/invites/pages/invites-page")).InvitesPage,
        }),
      },
      { path: "*", Component: NotFoundScreen },
    ],
  },
];
