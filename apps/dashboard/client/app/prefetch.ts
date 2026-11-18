import type { QueryClient } from "@tanstack/react-query";

let client: QueryClient | null = null;

/** The app's query client, so route loaders can warm the cache. Tests that don't register skip prefetching. */
export const registerQueryClient = (queryClient: QueryClient) => {
  client = queryClient;
};

/**
 * Route loader helper: start the queries a screen needs while its code chunk downloads
 * (instead of after it renders), without blocking navigation. Errors stay with the query: pass
 * `qc.query(...)` (it rejects, unlike the deprecated `prefetchQuery`) and the catch here swallows it.
 */
export const prefetch =
  (
    ...run: ((
      qc: QueryClient,
      args: { request: Request; params: Record<string, string | undefined> },
    ) => Promise<unknown>)[]
  ) =>
  (args: { request: Request; params: Record<string, string | undefined> }) => {
    if (client) for (const r of run) void r(client, args).catch(() => {});
    return null;
  };
