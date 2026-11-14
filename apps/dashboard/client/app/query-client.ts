import { MutationCache, QueryCache, QueryClient } from "@tanstack/react-query";
import { ApiError } from "../lib/api-error";

/**
 * Free tier: the dashboard shares the backend's Workers/D1 quota, so no refetch on window
 * focus, no polling, one retry for server/network errors only (4xx won't change on retry).
 * A 401 anywhere sends the admin to the login page.
 */
export function createQueryClient(onUnauthorized: () => void) {
  const onError = (error: unknown) => {
    if (error instanceof ApiError && error.code === "UNAUTHORIZED") onUnauthorized();
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
