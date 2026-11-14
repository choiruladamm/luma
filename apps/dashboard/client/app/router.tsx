import { createBrowserRouter } from "react-router";
import { LoginPage } from "../features/auth/pages/login-page";
import { InvitesPage } from "../features/invites/pages/invites-page";
import { OverviewPage } from "../features/overview/pages/overview-page";
import { UserDetailPage } from "../features/users/pages/user-detail-page";
import { UsersPage } from "../features/users/pages/users-page";
import { RequireSession } from "./require-session";

// Routing only: data comes from TanStack Query hooks inside the pages, not loaders/actions.
export const router = createBrowserRouter([
  { path: "/login", Component: LoginPage },
  {
    Component: RequireSession,
    children: [
      { index: true, Component: OverviewPage },
      { path: "users", Component: UsersPage },
      { path: "users/:id", Component: UserDetailPage },
      { path: "invites", Component: InvitesPage },
    ],
  },
]);
