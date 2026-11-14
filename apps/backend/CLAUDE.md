# Luma backend (Cloudflare Worker)

Hono API under `/v1` on Cloudflare Workers, D1 (SQLite) + Drizzle, R2, Better Auth (`bearer` plugin), Workers Rate Limiting. Bun is tooling only; the runtime is workerd. Full design: `docs/backend.md` (repo root). Read the relevant section before touching a feature.

## Commands

Run from the repo root:

| Command | Does |
|---|---|
| `make backend-install` | `bun install` |
| `make backend-dev` | Local Worker, env dev, `:8787`, local D1/R2. From a device: `make run f=dev` with `--dart-define=BACKEND_URL=http://<laptop-ip>:8787` |
| `make backend-test` | `tsc --noEmit` + vitest (workerd) + coverage |
| `make backend-types` | Regenerate `Env` types after editing `wrangler.jsonc` |
| `make backend-live` | Flutter client calls the deployed dev Worker |
| `make backend-e2e` | Dart sync E2E through a local `wrangler dev` |
| `make backend-migrate e=dev\|prod` | Apply D1 migrations remotely |
| `make backend-deploy e=dev\|prod` | Deploy; `prod` only from `master` (enforced). Full procedure: `/backend-deploy <env>` |

Bundle size check (3 MB compressed limit): `bun run size` from `apps/backend`.

## Code layout

```
src/
├── index.ts / app.ts     # Hono app: middleware + route mounting
├── env.ts                # AppEnv: Bindings + c.var (db, openrouter, user)
├── middleware/           # requestId, deps, killSwitch, bodyLimit, session, rateLimit, guard
├── auth/                 # Better Auth config, PBKDF2, invites, bearer session check
├── db/                   # Drizzle schema, Better Auth schema, shared user_storage
├── lib/                  # errors, crypto (AES-GCM), encoding, storage (per-user R2 rules)
├── clients/openrouter.ts # thin fetch wrapper (mocked in tests)
└── features/<feature>/   # account, ai-key, auth, backup, files, health, legal, sync
    ├── routes.ts         # Hono + zod validator, deps from c.var, no logic
    ├── service.ts        # business logic, dependencies passed as params
    ├── repo.ts           # every D1 query for the feature
    └── *.ts              # pure rules (e.g. sync/merge.ts), no I/O
```

- Middleware order: `requestId → (IP rateLimit + deps on all /v1) → killSwitch → bodyLimit → session → user rateLimit → validator → handler`, `onError` outside. Quota-bound features (files, backup, sync) use `featureGuard(flag)`. Kill switches run before D1/R2 is touched.
- All D1 queries live in `repo.ts` (plus `db/user-storage.ts` for shared tables); services never write SQL. Each repo function is one query-budget unit and its comment states the query count.
- Drizzle everywhere except `sync/repo.ts`, which uses raw SQL with `json_each` to fit 500-record batches in one statement.
- Features don't import other features, except account deletion calling `revokeKey`.
- R2 keys are always per user: `u/{userId}/...`; shared rules in `lib/storage.ts`.
- Validate every input with `@hono/zod-validator`. Errors are always `{"error": {"code", "message"}}`; the Flutter client maps `code` to an enum.

## Naming

- D1 tables/columns `snake_case`, plural tables; TS properties and JSON `camelCase` (`casing: "snake_case"` in Drizzle, no per-column names).
- Error codes `UPPER_SNAKE_CASE` (Better Auth style), URL paths lowercase `kebab-case`, JSON times ISO 8601 UTC, D1 times/booleans as integers.
- Better Auth trap: generated schema may hard-code camelCase column names (`text("emailVerified")`) that override `casing`. After generating, rename columns to `snake_case`, keep the properties.

## Schema changes (D1)

- Edit `src/db/schema.ts`, then `bun run db:generate` (drizzle-kit) to add a file under `migrations/`. Never edit an applied migration; add a new one.
- Tests apply migrations via `applyD1Migrations`, so a new migration is covered by `make backend-test`.
- Apply remotely with `make backend-migrate e=dev` before deploying code that needs it. Migrations must keep existing user data.
- The admin dashboard (`apps/dashboard`) reads the same D1 and imports `src/db/schema.ts`, `src/db/client.ts`, `src/auth/user-fields.ts`, `src/auth/invite.ts`, and `src/clients/openrouter.ts`; its tests read `src/features/ai-key/repo.ts`. Changing these files or the schema also runs `make dashboard-test`; keep them free of the backend `Env` type.

## Free tier (mandatory)

Read `docs/backend.md` (Aturan free tier) before adding or changing an endpoint. Server essentials:

- One request = one `db.batch()`; stream uploads/downloads (`c.req.raw.body` → R2), never buffer; ≤ 50 subrequests; per-user R2 and sync quotas; rate limits per user (and per IP for auth).
- Better Auth endpoints are allowlisted; don't expose new ones without updating the allowlist.
- Every endpoint change updates the budget table (Anggaran per aksi). A feature that doesn't fit gets redesigned, not moved to a paid plan.

## Tests

Vitest with `@cloudflare/vitest-plugin` (`cloudflareTest()`), local Miniflare D1/R2. Call the Worker via `exports.default.fetch` from `cloudflare:workers` (`SELF` is deprecated). Mock outbound calls (Google, OpenRouter) with MSW via `@msw/cloudflare`; unmocked outbound fetches return 599 `UNMOCKED_FETCH`.

- `test/unit/`: pure rules and services. `test/integration/`: each endpoint through the full app. `test/fixtures/contract/*.json`: shared with Dart tests.
- Every endpoint's integration test covers: success; 401 without/with bad token; 400/413 invalid or oversized body; user isolation (A can't read/write B); kill switch off → 503 with no D1/R2 access; 429 on rate limit; D1 query and subrequest counts within the budget table.
- Coverage: istanbul (V8 isn't supported in the Workers pool), 80% lines for `service.ts` and pure rule files.

## Per-issue workflow

1. Contract first: write request/response examples in `test/fixtures/contract/` before code.
2. Backend endpoint + tests, `make backend-test`, `make backend-deploy e=dev`.
3. Flutter: service → repository / ViewModel → UI, with tests.
4. End to end: `make backend-live` + try it in Luma Dev.
5. Merge the issue branch into `feat/backend` and push (no PR to `master` until the backend milestone lands). Close the issue with a summary of the checks run.

## Environments and secrets

- `wrangler.jsonc` envs `dev` and `prod`, each with its own D1, R2, and OpenRouter workspace. Custom domains `luma-api-dev.chrl.cloud` / `luma-api.chrl.cloud` (`*.workers.dev` is DNS-blocked on some Indonesian ISPs, kept as fallback). Client URLs: `backendUrls` in `apps/mobile/lib/data/services/backend_client.dart`.
- Secrets per env with `bunx wrangler secret put <NAME> --env <env>`; locally copy `.dev.vars.example` to `.dev.vars` (gitignored). Never put secrets in `wrangler.jsonc`.
