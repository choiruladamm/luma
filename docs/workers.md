---
type: explanation
purpose: How the Cloudflare Workers in this repo are laid out, share code, and stay consistent, for anyone adding or changing a Worker.
sections: [Workers, Workspace, Shared code, Conventions, Worker requirements, Behavior checks]
---

# Workers

## Workers

Two Hono Workers run on Cloudflare and share one D1 database per environment:

| Worker | Directory | Serves | Doc |
|---|---|---|---|
| `luma-api-{env}` | `apps/backend` | The mobile API under `/v1` | [backend.md](backend.md) |
| `luma-admin-{env}` | `apps/dashboard` | The admin API under `/api` and the React SPA | [dashboard.md](dashboard.md) |

Each Worker owns its routes, middleware, and features (`routes.ts` → `service.ts` → `repo.ts`). They never call each other over HTTP; they meet only in D1. Request budgets for both are in [budgets.md](budgets.md).

## Workspace

The TypeScript apps form one bun workspace declared in the root `package.json` (`apps/backend`, `apps/dashboard`, `packages/*`), with one `bun.lock` and one `node_modules` store, so a library both apps depend on directly (Hono, Drizzle, Better Auth, zod) resolves to the same copy in each. `make install` installs it.

Versions of libraries more than one workspace uses live once, in the root `catalog`; a workspace's `package.json` names them as `catalog:`. A library only one workspace uses keeps its version in that workspace.

Shared tool configuration sits at the root and each app extends it:

- `tsconfig.base.json`: compiler options. Each app adds its own `types` and `include`.
- `.oxlintrc.base.json`: plugins, categories, and rules. Each app adds its ignore patterns and its own exceptions, listed with their reasons in the app's `CLAUDE.md`. The packages' one exception: `typescript/no-unsafe-type-assertion` is off in `src/testing/**` of `worker-kit` and `core`, for JSON bodies and MSW params, as in the apps' tests.
- `.prettierrc.json`: formatting for every file.

## Shared code

Code both Workers need lives in `packages/core` (`@luma/core`), which neither Worker owns:

| Import | Contents |
|---|---|
| `@luma/core/db/schema`, `@luma/core/db/auth-schema` | The D1 schema; migrations are in `packages/core/migrations`, which both Workers' `wrangler.jsonc` name as `migrations_dir`. |
| `@luma/core/ai-keys` | `findUserKey`, the AI key lookup the backend issues keys from and the dashboard's tests check. |
| `@luma/core/db/client` | `createDb` and the `Db` type. |
| `@luma/core/auth/user-fields`, `@luma/core/auth/invite` | Luma's extra user columns and invite codes. |
| `@luma/core/openrouter` | The OpenRouter management client. |
| `@luma/core/encoding` | Base64, `csv`, and `DAY_MS`. |
| `@luma/core/testing/openrouter` | `fakeOpenRouter(network, options)`, the in-memory OpenRouter management API both Workers' tests mock; each Worker's `test/helpers/openrouter.ts` binds it to its MSW network. |

The package depends on no Worker's `Env`; it compiles against the Workers runtime types alone. Code only one Worker uses stays in that Worker. The backend's tests measure the package's coverage.

`packages/worker-kit` (`@luma/worker-kit`) is the request pipeline every Worker shares, with nothing Luma-specific in it: lint rejects its imports of a Worker or another `@luma` package.

| Import | Contents |
|---|---|
| `@luma/worker-kit/app` | `workerApp`, the pipeline start. |
| `@luma/worker-kit/errors` | `ApiError`, `BaseErrorCode`, `errorBody`, `onError`, `notFound`, `normalizeAuthError`. |
| `@luma/worker-kit/log` | `log.error`, `log.warn`, `log.info`. |
| `@luma/worker-kit/middleware` | `requestId`, `rateLimit`, `limitBody`, `killSwitch`, `validate`. |
| `@luma/worker-kit/testing/*` | Test helpers that load only in workerd: `setup` (D1 migrations, MSW network, 599 `UNMOCKED_FETCH`), `d1` (`countingD1`, one counter for statements that run), `golden` (`normalize`, `recordResponse`, `goldenJson`, `GOLDEN_NOW`). |

The kit's own tests run on Node (`make packages-test`) and hold 100% coverage, `testing/*` excluded: the Workers' tests exercise it. Both packages compile against `packages/workers-runtime.d.ts`, generated from `packages/wrangler.jsonc`.

`packages/contracts` (`@luma/contracts`) is the one source of the wire shapes, with zod as its only dependency: lint rejects its imports of a Worker or another `@luma` package.

| Import | Contents |
|---|---|
| `@luma/contracts/errors` | `errorBodySchema`; the codes each Worker throws (`backendErrorCode`, `dashboardErrorCode`, which its `ErrorCode` type comes from); `backendWireErrorCode`, which adds the Better Auth codes `/v1/auth/*` passes through, fixed by shape only because Better Auth owns that list. |
| `@luma/contracts/backend/*` | Request, query, and response schemas of the mobile API per feature (`health`, `account`, `ai`, `files`, `backups`, `sync`, `auth`), the limits they use, and the `z.infer` types. |
| `@luma/contracts/dashboard/*` | The same for the admin API (`users`, `invites`, `overview`, `auth`). |
| `@luma/contracts/fixtures/v1/*.json` | Request/response examples of the mobile API, read by the Worker tests and by the Dart client tests. |

Each Worker's `lib/errors.ts` derives its `ErrorCode` from the contract's list and fails to compile if the kit's `BaseErrorCode` is not a subset. The package's tests parse every fixture with its schema (`make packages-test`), and each Worker's golden test parses every JSON response with its schema.

`apps/dashboard/backend-vars.ts` reads the backend's feature flags, OpenRouter workspace, and AI budget from `apps/backend/wrangler.jsonc` at build time, because those runtime vars belong to the backend's configuration.

## Conventions

Rules both Workers follow; each Worker's doc has its own routes, guards, and codes.

- **Imports.** A Worker never imports from another Worker's directory, only from `packages/*`; lint rejects `apps/*` paths. A feature never imports another feature (the backend's account deletion calling `revokeKey` is the one exception).
- **Paths and versions.** The backend serves `/v1/*`; the dashboard serves `/api/*`, which ships with its SPA and so has no version.
- **Pipeline start.** Each Worker passes its Hono app through `workerApp` (`@luma/worker-kit/app`), which installs `requestId`, `notFound`, and `onError` before the Worker's own middleware.
- **Request ids.** Every response, Better Auth's included, carries `x-request-id`, and every log line of that request includes it.
- **Responses.** JSON field names are camelCase. A success returns the resource itself, without an envelope. Request and response schemas live in `@luma/contracts`; routes validate with them and services type their results with `z.infer` of them, so no DTO type is hand-written.
- **Errors.** Every error is `{error: {code, message}}` with an `UPPER_SNAKE_CASE` code that clients branch on; the message is for people. Code throws `ApiError`; each Worker's `lib/errors.ts` takes its codes from the contract's list, which includes the kit's `BaseErrorCode`. A 4xx Hono `HTTPException` gets the base code for its status, unknown routes return 404 `NOT_FOUND`, and an unexpected failure returns 500 `INTERNAL_ERROR`. `normalizeAuthError` wraps Better Auth's JSON errors in the same shape, keeping Better Auth's code. Backend codes: [backend.md](backend.md) (Request pipeline and API conventions); dashboard codes: [dashboard.md](dashboard.md) (API routes and errors).
- **Logs.** Worker code logs only through `log` (`@luma/worker-kit/log`); lint rejects `console` outside scripts and tests. A line is single-line JSON with a `message` and the `requestId`. Unexpected failures and handled upstream failures are logged as errors; dashboard mutations also log an `audit` line. Tokens, keys, and sync record bodies never reach a log.
- **Validation and limits.** Inputs go through the kit's `validate` (400 `BAD_REQUEST`, with the route's message or zod's first issue). Bodies are size-limited with `limitBody` before parsing (413 `PAYLOAD_TOO_LARGE`), rate limits return 429 `RATE_LIMITED` with `Retry-After`, and a `killSwitch` var that isn't `"true"` returns 503 `SERVICE_DISABLED`.

## Worker requirements

A Worker in this repo has:

- a wrangler config with `observability` logs and traces enabled and bindings typed by `wrangler types`, never a hand-written `Env`;
- an app built with `workerApp` and its error codes in `lib/errors.ts`;
- the shared tool configuration from [Workspace](#workspace);
- a golden HTTP test and coverage thresholds (below), plus the per-endpoint integration cases listed in its `CLAUDE.md`;
- a row per endpoint in the [budgets.md](budgets.md) Per-action budgets table;
- `make <worker>-test` in CI and a deploy step in `.github/workflows/deploy.yml`.

## Behavior checks

Each Worker has a golden HTTP test (`test/golden/http.test.ts`) that records every route's status, headers, cookies, body, D1 queries, and outbound fetches under a fixed clock, plus R2 operations for the backend. A change in behavior shows up as a diff in `http.golden.json`. Coverage thresholds in each `vitest.config.ts` sit at the current coverage and only go up for the code they measure; when code moves into a package that has its own tests, the Worker's threshold is re-measured in that commit.
