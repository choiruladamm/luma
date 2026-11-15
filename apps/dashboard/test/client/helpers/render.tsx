import { QueryClientProvider } from "@tanstack/react-query";
import { render } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { createMemoryRouter, type RouteObject, RouterProvider } from "react-router";
import { createQueryClient } from "../../../client/app/query-client";
import { routes } from "../../../client/app/routes";

// Screens are lazy chunks; the first import transforms the module (~2s cold), longer than
// findBy waits. Load them all once up front so tests time the UI, not the bundler.
const preload = (list: RouteObject[]): unknown[] =>
  list.flatMap((r) => [typeof r.lazy === "function" ? r.lazy() : undefined, ...preload(r.children ?? [])]);
await Promise.all(preload(routes));

/** The whole app (routes, guard, shell, query client) at `path`, like the browser gets it. */
export function renderApp(path = "/") {
  const router = createMemoryRouter(routes, { initialEntries: [path] });
  const queryClient = createQueryClient(() => void router.navigate("/login", { replace: true }));
  const user = userEvent.setup();
  const view = render(
    <QueryClientProvider client={queryClient}>
      <RouterProvider router={router} />
    </QueryClientProvider>,
  );
  return { ...view, router, queryClient, user };
}
