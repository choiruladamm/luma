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
- `.oxlintrc.base.json`: plugins, categories, and rules. Each app adds its ignore patterns and its own exceptions, listed with their reasons in the app's `CLAUDE.md`.
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

The package depends on no Worker's `Env`; it compiles against the Workers runtime types alone. Code only one Worker uses stays in that Worker. The backend's tests measure the package's coverage.

`apps/dashboard/backend-vars.ts` reads the backend's feature flags, OpenRouter workspace, and AI budget from `apps/backend/wrangler.jsonc` at build time, because those runtime vars belong to the backend's configuration.

## Conventions

Rules both Workers follow; each Worker's doc has its own routes, guards, and codes.

- **Imports.** A Worker never imports from another Worker's directory, only from `packages/*`; lint rejects `apps/*` paths. A feature never imports another feature (the backend's account deletion calling `revokeKey` is the one exception).
- **Paths and versions.** The backend serves `/v1/*`; the dashboard serves `/api/*`, which ships with its SPA and so has no version.
- **Request ids.** Every response the Worker builds carries `x-request-id`, and every log line of that request includes it. Better Auth responses pass through without the header (#259).
- **Responses.** JSON field names are camelCase. A success returns the resource itself, without an envelope.
- **Errors.** Every error is `{error: {code, message}}` with an `UPPER_SNAKE_CASE` code that clients branch on; the message is for people. Unknown routes return 404 `NOT_FOUND`, and an unexpected failure returns 500 `INTERNAL_ERROR`. Backend codes: [backend.md](backend.md) (Request pipeline and API conventions); dashboard codes: [dashboard.md](dashboard.md) (API routes and errors).
- **Logs.** Logs are single-line JSON with a `message` and the `requestId`. Unexpected failures and handled upstream failures are logged; dashboard mutations also log an `audit` line. Tokens, keys, and sync record bodies never reach a log.
- **Limits.** JSON bodies are size-limited before parsing (413 `PAYLOAD_TOO_LARGE`), and rate limits return 429 `RATE_LIMITED` with `Retry-After`.

## Worker requirements

A Worker in this repo has:

- a wrangler config with `observability` logs enabled and bindings typed by `wrangler types`, never a hand-written `Env`;
- the shared tool configuration from [Workspace](#workspace);
- a golden HTTP test and coverage thresholds (below), plus the per-endpoint integration cases listed in its `CLAUDE.md`;
- a row per endpoint in the [budgets.md](budgets.md) Per-action budgets table;
- `make <worker>-test` in CI and a deploy step in `.github/workflows/deploy.yml`.

## Behavior checks

Each Worker has a golden HTTP test (`test/golden/http.test.ts`) that records every route's status, headers, cookies, body, D1 queries, and outbound fetches under a fixed clock, plus R2 operations for the backend. A change in behavior shows up as a diff in `http.golden.json`. Coverage thresholds in each `vitest.config.ts` sit at the current coverage and only go up.
