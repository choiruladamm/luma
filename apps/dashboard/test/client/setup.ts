import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { setupServer } from "msw/node";
import { afterAll, afterEach, beforeAll } from "vitest";
import { useToastStore } from "../../client/stores/toast-store";
import { useUiStore } from "../../client/stores/ui-store";
import { defaultHandlers } from "./helpers/handlers";

/** Every /api call goes through MSW; an unhandled request fails the test. */
export const server = setupServer(...defaultHandlers());

// happy-dom reports an English browser; assertions use the Indonesian copy, so pin it.
// English rendering has its own tests (i18n.test.ts, the language switch in auth.test.tsx).
useUiStore.setState({ lang: "id" });

beforeAll(() => server.listen({ onUnhandledFrame: "error" }));
afterEach(() => {
  cleanup();
  server.resetHandlers();
  localStorage.clear();
  delete document.documentElement.dataset.theme;
  document.documentElement.lang = "id";
  useToastStore.setState({ toast: null });
  useUiStore.setState({ theme: "system", lang: "id", openMenu: null });
});
afterAll(() => server.close());
