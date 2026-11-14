import { QueryClientProvider } from "@tanstack/react-query";
import { RouterProvider } from "react-router/dom";
import { createQueryClient } from "./query-client";
import { router } from "./router";

const queryClient = createQueryClient(() => {
  queryClient.clear();
  void router.navigate("/login", { replace: true });
});

export function Providers() {
  return (
    <QueryClientProvider client={queryClient}>
      <RouterProvider router={router} />
    </QueryClientProvider>
  );
}
