import type { RouteObject } from "react-router";
import { sessionQuery } from "../features/auth/queries/use-session";
import { invitesQuery } from "../features/invites/queries/use-invites";
import { overviewQuery } from "../features/overview/queries/use-overview";
import { userDetailQuery } from "../features/users/queries/use-user-detail";
import { DEFAULT_USERS_PARAMS, parseUsersParams } from "../features/users/hooks/use-users-params";
import { usersQuery } from "../features/users/queries/use-users";
import { prefetch } from "./prefetch";

// Routing only: screens read their data through TanStack Query hooks. Every screen is its own
// chunk (lazy), so /login doesn't download the admin screens; each route's loader starts that
// screen's queries in parallel with the chunk download instead of after it renders.
// Shared by the browser router and the tests.
export const routes: RouteObject[] = [
  { path: "/login", lazy: async () => ({ Component: (await import("../features/auth/pages/login-page")).LoginPage }) },
  {
    // The shell shows nav counts from the overview, so every admin screen warms it too.
    loader: prefetch(
      (qc) => qc.prefetchQuery(sessionQuery),
      (qc) => qc.prefetchQuery(overviewQuery),
    ),
    // Blank while the first loader + chunk settle, same as the guard's pending state.
    HydrateFallback: () => null,
    lazy: async () => ({ Component: (await import("./require-session")).RequireSession }),
    children: [
      {
        index: true,
        loader: prefetch((qc) => qc.prefetchQuery(usersQuery(DEFAULT_USERS_PARAMS))),
        lazy: async () => ({ Component: (await import("../features/overview/pages/overview-page")).OverviewPage }),
      },
      {
        path: "users",
        loader: prefetch((qc, { request }) => qc.prefetchQuery(usersQuery(parseUsersParams(new URL(request.url).searchParams)))),
        lazy: async () => ({ Component: (await import("../features/users/pages/users-page")).UsersPage }),
      },
      {
        path: "users/:id",
        loader: prefetch((qc, { params }) => qc.prefetchQuery(userDetailQuery(params.id ?? ""))),
        lazy: async () => ({ Component: (await import("../features/users/pages/user-detail-page")).UserDetailPage }),
      },
      {
        path: "invites",
        loader: prefetch((qc) => qc.prefetchQuery(invitesQuery())),
        lazy: async () => ({ Component: (await import("../features/invites/pages/invites-page")).InvitesPage }),
      },
    ],
  },
];
