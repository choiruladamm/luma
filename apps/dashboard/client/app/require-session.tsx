import { Navigate } from "react-router";
import { ErrorState } from "../components/ui/states";
import { useSession } from "../features/auth/queries/use-session";
import { AppShell } from "./app-shell";

/**
 * Route guard: signed out (`null`) → /login. A failed check (network, 429) is not "signed
 * out", so it shows a retry instead of bouncing the admin to the login page. The worker
 * enforces auth on its own; this only avoids a broken screen.
 */
export function RequireSession() {
  const session = useSession();
  if (session.isPending) return null;
  if (session.isError) {
    return (
      <main className="flex min-h-dvh items-center justify-center bg-page px-4">
        <section className="w-full max-w-[480px] rounded-card bg-sheet">
          <ErrorState title="Sesi gagal dicek" message={session.error.message} onRetry={() => void session.refetch()} />
        </section>
      </main>
    );
  }
  if (!session.data) return <Navigate to="/login" replace />;
  return <AppShell />;
}
