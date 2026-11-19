import { setupNetwork } from "@msw/cloudflare";
import { applyD1Migrations, env } from "cloudflare:test";
import { HttpResponse, http } from "msw";
import { afterAll, afterEach, beforeAll, beforeEach } from "vitest";

/**
 * Test setup shared by the Workers: migrates D1 and mocks every outbound fetch with
 * `network.use(...)`. An unmocked fetch reaches the last handler and fails with 599,
 * so an unexpected subrequest shows up in tests.
 */
export async function setupWorkerTests() {
  await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);

  const network = setupNetwork();
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
  return network;
}
