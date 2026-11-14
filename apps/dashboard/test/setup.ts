import { setupNetwork } from "@msw/cloudflare";
import { applyD1Migrations, env } from "cloudflare:test";
import { HttpResponse, http } from "msw";
import { afterAll, afterEach, beforeAll, beforeEach } from "vitest";

await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);

/**
 * Semua fetch keluar (Google, OpenRouter) di-mock lewat `network.use(...)`.
 * Fetch yang gak di-mock jatuh ke handler terakhir dan gagal keras, jadi
 * subrequest tak terduga ketahuan di test.
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
