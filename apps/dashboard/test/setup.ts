import { setupNetwork } from "@msw/cloudflare";
import { applyD1Migrations, env } from "cloudflare:test";
import { HttpResponse, http } from "msw";
import { afterAll, afterEach, beforeAll, beforeEach } from "vitest";

await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);

/**
 * Every outbound fetch (Google, OpenRouter) is mocked with `network.use(...)`.
 * Unmocked fetches hit the last handler and fail loudly, so unexpected
 * subrequests show up in tests.
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
