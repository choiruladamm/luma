import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { setupServer } from "msw/node";
import { afterAll, afterEach, beforeAll } from "vitest";
import { useToastStore } from "../../client/stores/toast-store";
import { useUiStore } from "../../client/stores/ui-store";
import { defaultHandlers } from "./helpers/handlers";

/** Every /api call goes through MSW; an unhandled request fails the test. */
export const server = setupServer(...defaultHandlers());

beforeAll(() => server.listen({ onUnhandledFrame: "error" }));
afterEach(() => {
  cleanup();
  server.resetHandlers();
  localStorage.clear();
  delete document.documentElement.dataset.theme;
  useToastStore.setState({ toast: null });
  useUiStore.setState({ theme: "system", openMenu: null });
});
afterAll(() => server.close());
