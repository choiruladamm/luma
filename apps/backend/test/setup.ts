import { setupNetwork } from "@msw/cloudflare";
import { applyD1Migrations, env } from "cloudflare:test";
import { HttpResponse, http } from "msw";
import { afterAll, afterEach, beforeAll, beforeEach } from "vitest";

await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);

/**
 * All outbound fetches (Google, OpenRouter) are mocked via `network.use(...)`.
 * An unmocked fetch falls through to the last handler and fails hard, so an
 * unexpected subrequest is caught in tests.
 */
export const network = setupNetwork();

beforeAll(() => network.enable());
beforeEach(() =>
  network.use(
    http.all("*", ({ request }) =>
      HttpResponse.json(
        { error: { code: "UNMOCKED_FETCH", message: `${request.method} ${request.url}` } },
        { status: 599 },
      ),
    ),
  ),
);
afterEach(() => network.resetHandlers());
afterAll(() => network.disable());
