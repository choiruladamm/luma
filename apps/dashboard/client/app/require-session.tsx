import { Navigate, Outlet } from "react-router";
import { useSession } from "../features/auth/queries/use-session";

/** Route guard: no admin session → /login. The worker enforces this too; this only avoids a broken screen. */
export function RequireSession() {
  const session = useSession();
  if (session.isPending) return null;
  if (!session.data) return <Navigate to="/login" replace />;
  return <Outlet />;
}
