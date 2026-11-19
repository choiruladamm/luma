import { MutationCache, QueryCache, QueryClient } from "@tanstack/react-query";
import { getI18n } from "../i18n";
import { ApiError, errorText } from "../lib/api-error";
import { toast } from "../stores/toast-store";

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
    queryCache: new QueryCache({
      onError: (error, query) => {
        onError(error);
        // Screens keep showing cached data when a refresh fails (they swap to an error state only
        // when there is nothing to show), so the failure surfaces here instead.
        const leaving =
          error instanceof ApiError && ["UNAUTHORIZED", "ACCESS_EXPIRED"].includes(error.code);
        if (query.state.data === undefined || leaving) return;
        const { t } = getI18n();
        toast(errorText(error, t), {
          tone: "error",
          action: { label: t.common.retry, onClick: () => void query.fetch() },
        });
      },
    }),
    mutationCache: new MutationCache({ onError }),
    defaultOptions: {
      queries: {
        staleTime: 60_000,
        refetchOnWindowFocus: false,
        refetchOnReconnect: false,
        retry: (failures, error) =>
          failures < 1 && !(error instanceof ApiError && error.status >= 400 && error.status < 500),
      },
      mutations: { retry: false },
    },
  });
}
