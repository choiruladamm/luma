# Luma backend (Cloudflare Worker)

Hono API under `/v1` on Workers, D1 + Drizzle, R2, Better Auth (`bearer` plugin), Workers Rate Limiting. Bun is tooling only; the runtime is workerd. Design: `docs/backend.md`; read the section for a feature before touching it.

## Commands

- `make backend-test` (tsc + vitest in workerd + coverage) is the check for this app. Bundle limit 3 MB compressed: `bun run size` from `apps/backend`.
- After editing `wrangler.jsonc`: `make backend-types`.
- Deploys go through the `/backend-deploy <env>` skill. `make backend-deploy e=prod` refuses outside `master`; `make backend-migrate e=prod` doesn't check the branch, so run it from `master` only.

## Code rules

- Per feature: `routes.ts` (validator + wiring, no logic) → `service.ts` (logic, deps passed as params) → `repo.ts` (every D1 query; services never write SQL). Each repo function is one query-budget unit and its comment states the query count.
- requestId, IP rate limit, and deps run on all `/v1`; kill switch, body limit, session, and user rate limit attach per route group (`app.ts`). Kill switches run before D1/R2 is touched. Quota-bound features (files, backup, sync) use `featureGuard(flag)`.
- Drizzle everywhere except `sync/repo.ts`: raw SQL with `json_each` fits a 500-record batch in one statement.
- Features don't import each other, except account deletion calling `revokeKey`.
- R2 keys are always per user, `u/{userId}/...`, through `lib/storage.ts`.
- Validate every input with `@hono/zod-validator`. Errors are `{"error": {"code", "message"}}` with `UPPER_SNAKE_CASE` codes; the Flutter client maps `code` to an enum.
- Better Auth trap: its generated schema can hard-code camelCase column names (`text("emailVerified")`) that override Drizzle `casing: "snake_case"`. After generating, rename the columns to snake_case and keep the properties.

## Free tier

Read `docs/backend.md` (Aturan free tier) before adding or changing an endpoint.

- One request = one `db.batch()`; stream uploads/downloads (`c.req.raw.body` → R2), never buffer; ≤ 50 subrequests; per-user R2 and sync quotas; rate limits per user (and per IP for auth).
- Better Auth endpoints are allowlisted (`AUTH_PATHS` in `features/auth/routes.ts`); exposing a new one updates the allowlist.
- Every endpoint change updates the budget table (Anggaran per aksi). A feature that doesn't fit gets redesigned, not moved to a paid plan.

## Schema changes (D1)

- Edit `src/db/schema.ts`, then `bun run db:generate`. Add a new migration; applied ones stay untouched. Migrations keep existing user data.
- Apply remotely (`make backend-migrate e=dev`) before deploying code that needs it.
- The dashboard reads the same D1 and imports `src/db/schema.ts`, `src/db/client.ts`, `src/auth/user-fields.ts`, `src/auth/invite.ts`, and `src/clients/openrouter.ts`; its tests read `src/features/ai-key/repo.ts`, and its build reads `SYNC_ENABLED`, `BACKUP_ENABLED`, `AI_KEY_ENABLED`, `OPENROUTER_WORKSPACE_ID`, `AI_MONTHLY_BUDGET_USD` from this `wrangler.jsonc`. Changing any of these, or the schema, also runs `make dashboard-test`; keep these files free of the backend `Env` type.

## Tests

Vitest with `@cloudflare/vitest-plugin`, local Miniflare D1/R2. Call the Worker via `exports.default.fetch` from `cloudflare:workers` (`SELF` is deprecated). Mock outbound calls (Google, OpenRouter) with MSW via `@msw/cloudflare`; an unmocked fetch returns 599 `UNMOCKED_FETCH`. Shared helpers (sign-up, invites, budget counting, contract fixtures) live in `test/helpers/`.

Every endpoint's integration test covers: success; 401 without/with a bad token; 400/413 invalid or oversized body; user isolation (A can't read/write B); kill switch off → 503 with no D1/R2 access; 429 on rate limit; D1 query and subrequest counts within the budget table.

## Per-issue flow

1. Contract first: request/response examples in `test/fixtures/contract/` before code.
2. Endpoint + tests, `make backend-test`, deploy to dev.
3. Flutter: service → repository / ViewModel → UI, with tests.
4. End to end: `make backend-live` + try it in Luma Dev.

## Environments and secrets

- `*.workers.dev` is DNS-blocked on some Indonesian ISPs, so clients use the custom domains (`backendUrls` in `apps/mobile/lib/data/services/backend_client.dart`).
- Secrets per env with `bunx wrangler secret put <NAME> --env <env>`; locally copy `.dev.vars.example` to `.dev.vars` (gitignored).
- `AI_KEY_ENC_SECRET` stays fixed after the first prod deploy: stored AI keys can't be decrypted with a new one.
