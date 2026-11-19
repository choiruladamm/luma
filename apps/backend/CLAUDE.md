# Luma backend (Cloudflare Worker)

Hono API under `/v1` on Workers, D1 + Drizzle, R2, Better Auth (`bearer` plugin), Workers Rate Limiting. Bun is tooling only; the runtime is workerd. Design: `docs/backend.md`; read the section for a feature before touching it. Rules shared with the dashboard Worker (workspace, conventions): `docs/workers.md`.

## Commands

- `make backend-test` (oxlint + Prettier check, tsc, vitest in workerd + coverage) is the check for this app; `bun run format` fixes formatting. Bundle limit 3 MB compressed: `bun run size` from `apps/backend`.
- After editing `wrangler.jsonc`: `make backend-types`.

## Lint exceptions

`.oxlintrc.json` can't hold comments, so every rule it turns off or scopes is listed here. Inline `oxlint-disable` comments carry their own reason. A new exception adds a line.

- `no-await-in-loop`, off: R2 pagination follows cursors, and the rate-limit tests send requests in order on purpose.
- `typescript/no-unsafe-type-assertion`, off in `test/**`: JSON bodies and the `RateLimit`/`R2Bucket` mocks.
- `vitest/expect-expect` in `test/**`: `expectContract` counts as an assertion.
- `vitest/valid-expect` in `test/**`: `maxArgs: 2`, because `expect(x, message)` is intentional.
- Deploys run in GitHub Actions on push to `dev`/`master` (`.github/workflows/deploy.yml`); the `/backend-deploy <env>` skill is the manual fallback. `make backend-deploy e=prod` and `make backend-migrate e=prod` refuse outside `master`.

## Code rules

- Per feature: `routes.ts` (validator + wiring, no logic) → `service.ts` (logic, deps passed as params) → `repo.ts` (every D1 query; services never write SQL). Each repo function is one query-budget unit and its comment states the query count.
- requestId, IP rate limit, and deps run on all `/v1`; kill switch, body limit, session, and user rate limit attach per route group (`app.ts`). Kill switches run before D1/R2 is touched. Quota-bound features (files, backup, sync) use `featureGuard(flag)`.
- Drizzle everywhere except `sync/repo.ts`: raw SQL with `json_each` fits a 500-record batch in one statement.
- Features don't import each other, except account deletion calling `revokeKey`.
- R2 keys are always per user, `u/{userId}/...`, through `lib/storage.ts`.
- Validate every input with `validate` from `@luma/worker-kit/middleware` and the schema from `@luma/contracts` (request and response types are `z.infer` of it, never hand-written), and throw `ApiError` from `lib/errors.ts` (backend codes listed there). Errors are `{"error": {"code", "message"}}` with `UPPER_SNAKE_CASE` codes; the Flutter client maps `code` to an enum. Shared middleware and `log` come from `@luma/worker-kit` (`docs/workers.md`).
- Better Auth trap: its generated schema can hard-code camelCase column names (`text("emailVerified")`) that override Drizzle `casing: "snake_case"`. After generating, rename the columns to snake_case and keep the properties.

## Free tier

Read `docs/budgets.md` (Free-tier limits and Server request policy) before adding or changing an endpoint.

- One request = one `db.batch()`; stream uploads/downloads (`c.req.raw.body` → R2), never buffer; ≤ 50 subrequests; per-user R2 and sync quotas; rate limits per user (and per IP for auth).
- Better Auth endpoints are allowlisted (`AUTH_PATHS` in `features/auth/routes.ts`); exposing a new one updates the allowlist.
- Every endpoint change updates the budget table (`docs/budgets.md`, Per-action budgets). A feature that doesn't fit gets redesigned, not moved to a paid plan.

## Schema changes (D1)

- The schema and migrations live in `packages/core` (`@luma/core`), shared with the dashboard. Edit `packages/core/src/db/schema.ts`, then `bun run db:generate` from `packages/core`. Add a new migration; applied ones stay untouched. Migrations keep existing user data.
- Apply remotely (`make backend-migrate e=dev`) before deploying code that needs it.
- Local D1 (shared by `backend-dev` and `dashboard-dev`, state in `apps/backend/.wrangler/state`) is not migrated by either: run `make backend-migrate-local` on a fresh clone and after pulling a new migration, or sign-in fails with `INTERNAL_ERROR` ("Failed query ... sessions").
- The dashboard reads the same D1 through `@luma/core`, and its build reads `SYNC_ENABLED`, `BACKUP_ENABLED`, `AI_KEY_ENABLED`, `OPENROUTER_WORKSPACE_ID`, `AI_MONTHLY_BUDGET_USD` from this `wrangler.jsonc`. Changing `@luma/core` or any of these vars also runs `make dashboard-test`.

## Tests

Vitest with `@cloudflare/vitest-plugin`, local Miniflare D1/R2. Call the Worker via `exports.default.fetch` from `cloudflare:workers` (`SELF` is deprecated). Mock outbound calls (Google, OpenRouter) with MSW via `@msw/cloudflare`; an unmocked fetch returns 599 `UNMOCKED_FETCH`. `test/setup.ts` calls `setupWorkerTests` and `countingD1` comes from `@luma/worker-kit/testing`; the OpenRouter fake is `@luma/core/testing/openrouter`. Other shared helpers (sign-up, invites, budget counting, contract fixtures) live in `test/helpers/`.

`test/golden/http.test.ts` records every route's status, headers, body, D1 queries, and subrequests in `http.golden.json`. A behavior change shows up as a diff there: review it, then accept it with `bunx vitest run test/golden -u`. Coverage thresholds in `vitest.config.ts` only go up (rule: `docs/workers.md`, Behavior checks).

Every endpoint's integration test covers: success; 401 without/with a bad token; 400/413 invalid or oversized body; user isolation (A can't read/write B); kill switch off → 503 with no D1/R2 access; 429 on rate limit; D1 query and subrequest counts within the budget table.

## Per-issue flow

1. Contract first: the zod schemas in `packages/contracts/src/backend/` and request/response examples in `packages/contracts/fixtures/v1/` before code.
2. Endpoint + tests, `make backend-test`, deploy to dev.
3. Flutter: service → repository / ViewModel → UI, with tests.
4. End to end: `make backend-live` + try it in Luma Dev.

## Environments and secrets

- `*.workers.dev` is DNS-blocked on some Indonesian ISPs, so clients use the custom domains (`backendUrls` in `apps/mobile/lib/data/services/backend_client.dart`).
- Secrets per env with `bunx wrangler secret put <NAME> --env <env>`; locally copy `.dev.vars.example` to `.dev.vars` (gitignored).
- `AI_KEY_ENC_SECRET` stays fixed after the first prod deploy: stored AI keys can't be decrypted with a new one.
