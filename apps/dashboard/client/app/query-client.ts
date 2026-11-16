import { MutationCache, QueryCache, QueryClient } from "@tanstack/react-query";
import { ApiError } from "../lib/api-error";

/**
 * Free tier: the dashboard shares the backend's Workers/D1 quota, so no refetch on window
 * focus (only the session query opts in, at most hourly), no polling, one retry for server/network errors only (4xx won't change on retry).
 * A 401 anywhere sends the admin to the login page; an expired Cloudflare Access session reloads
 * the page so Access can show its sign-in (a page load gets its redirect, fetch gets a 401).
 */
export function createQueryClient(onUnauthorized: () => void, onAccessExpired: () => void) {
  const onError = (error: unknown) => {
    if (!(error instanceof ApiError)) return;
    if (error.code === "UNAUTHORIZED") onUnauthorized();
    if (error.code === "ACCESS_EXPIRED") onAccessExpired();
  };
  return new QueryClient({
    queryCache: new QueryCache({ onError }),
    mutationCache: new MutationCache({ onError }),
    defaultOptions: {
      queries: {
        staleTime: 60_000,
        refetchOnWindowFocus: false,
        refetchOnReconnect: false,
        retry: (failures, error) => failures < 1 && !(error instanceof ApiError && error.status >= 400 && error.status < 500),
      },
      mutations: { retry: false },
    },
  });
}
