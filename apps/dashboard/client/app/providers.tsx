import { QueryClientProvider } from "@tanstack/react-query";
import { useEffect } from "react";
import { RouterProvider } from "react-router/dom";
import { registerQueryClient } from "./prefetch";
import { createQueryClient } from "./query-client";
import { router } from "./router";
import { applyTheme, useUiStore } from "../stores/ui-store";

const queryClient = createQueryClient(
  () => {
    queryClient.clear();
    void router.navigate("/login", { replace: true });
  },
  () => window.location.reload(),
);
registerQueryClient(queryClient);

export function Providers() {
  const theme = useUiStore((s) => s.theme);
  useEffect(() => applyTheme(theme), [theme]);
  return (
    <QueryClientProvider client={queryClient}>
      <RouterProvider router={router} />
    </QueryClientProvider>
  );
}
