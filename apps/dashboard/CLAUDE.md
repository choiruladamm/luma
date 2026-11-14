# Luma admin dashboard (Cloudflare Worker)

Admin-only Worker `luma-admin-{env}`: Hono API under `/api` on the same D1 as the backend env, behind Cloudflare Access + a second Better Auth instance (cookie sessions, Google redirect only). The React SPA (Workers Static Assets) comes later. Full design: `docs/dashboard.md` (repo root). Read it before touching auth, middleware, or an endpoint.

## Commands

Run from the repo root:

| Command | Does |
|---|---|
| `make dashboard-install` | `bun install` |
| `make dashboard-dev` | Vite dev server running the Worker (`CLOUDFLARE_ENV=dev`), `http://localhost:5173`, shares the local D1 of `make backend-dev`. Secrets in `.dev.vars` (copy `.dev.vars.example`) |
| `make dashboard-test` | `tsc --noEmit` + vitest (workerd), backend migrations applied |
| `make dashboard-deploy e=dev\|prod` | `CLOUDFLARE_ENV=<env> vite build` then `wrangler deploy` (uses the flattened `dist/` config); `prod` only from `master` (enforced) |

Backend vars the dashboard reads (switches, OpenRouter workspace, AI budget) come from `apps/backend/wrangler.jsonc` of the same env via `backend-vars.ts`, injected by `vite.config.ts` and `vitest.config.ts`; their types are in `worker/backend-env.d.ts`. Never copy them into this `wrangler.jsonc`. The Cloudflare env is picked by `CLOUDFLARE_ENV` at dev/build time, never `wrangler deploy --env`. `wrangler secret put --env <env>` still reads `wrangler.jsonc` and works as usual. After editing `wrangler.jsonc`: `bunx wrangler types --env dev --strict-vars false` from `apps/dashboard` (needs `.dev.vars` so secrets get typed).

## Code layout

Same pattern as `apps/backend/src`:

```
worker/
├── index.ts             # middleware order, Better Auth allowlist, route mounting, export AppType
├── env.ts               # AppEnv + `factory` (createFactory<AppEnv>)
├── auth/
│   ├── auth.ts          # Better Auth instance
│   ├── admin.ts         # isAdmin (ADMIN_EMAILS)
│   └── session.ts       # session cookie name + session/user queries for auth
├── middleware/          # request-id, security-headers, rate-limit (IP + per admin), require-admin, same-origin, validate
├── lib/                 # errors (ApiError, onError), audit
└── features/<feature>/
    ├── routes.ts        # Hono + validate(), deps from c.var, no logic; chained for AppType
    ├── service.ts       # business logic, dependencies passed as params
    └── repo.ts          # every D1 query of the feature
client/                  # React SPA, see "Client" below
```

- Middleware order: `securityHeaders → requestId → IP rateLimit → [/api/auth/* allowlist → Better Auth] → requireAdmin → requireSameOriginJson → rateLimitAdmin → validate → handler`. `requireAdmin` is global on `/api/*`; never add per-route auth or mount routes before it.
- Build the app, middleware, and feature routers from `factory` in `env.ts`. Feature routes are chained (`factory.createApp().get(...).post(...)`) and mounted with `.route()` on `routes` in `index.ts`, so `AppType` carries their types.
- Features don't import each other. Each `repo.ts` function is one query-budget unit; its comment states the query count.
- Better Auth endpoints are allowlisted in `AUTH_ROUTES`; anything else under `/api/auth/*` is 404. Don't add one without updating `docs/dashboard.md`.
- Never build the Better Auth instance outside `/api/auth/*` (tens of ms CPU). `requireAdmin` verifies the cookie HMAC itself, then one D1 join.
- Metadata only: never select `records`, `key_enc`, or session tokens into a response. Pick columns explicitly.
- Free tier: same per-account Workers/D1 quota as the backend. Every endpoint updates the budget table in `docs/backend.md` (Anggaran per aksi). No polling.
- Code comments in this app are in English (docs, issues, and API error copy stay as they are).

## Client (`client/`)

Stack: React, React Router (routing only), TanStack Query over `hc<AppType>()`, RHF + zod, TanStack Table, Zustand. No Axios, no React Router loaders/actions. Files are kebab-case.

- One-way flow: `pages → (feature hooks + queries) → api → lib/api-client`. Components only take props; features don't import each other.
- `features/*/api/`: raw `hc` calls through `unwrap()` → data or `ApiError`; no React. `queries/`: the only place for `useQuery`/`useMutation`, keys in `query-keys.ts`. `hooks/`: client logic that never calls the API. `schemas/`: zod for forms, mirroring worker limits (the worker stays the authority).
- `client/` imports from `worker/` with `import type` only. Better Auth routes aren't in `AppType`; `features/auth/api` uses plain `fetch`.
- Keep the TanStack Query defaults in `app/query-client.ts` (no focus refetch, no polling): the dashboard shares the backend's free-tier quota.
- Zustand (`stores/`) holds UI state only, never API data.
- Static files don't pass through the Worker: their security headers live in `public/_headers`.
- `tsconfig.client.json` checks `client/` (DOM + JSX); `make dashboard-test` runs it. `client/lib` has unit tests in `test/unit/`.

## Shared code with the backend

Imported relatively from `../backend/src`, never copied or edited from here (`db/schema.ts`, `db/client.ts`, `auth/user-fields.ts`, `auth/invite.ts`, `clients/openrouter.ts`). Don't import backend files that touch the backend `Env` (e.g. `features/*/service.ts`): tsc checks them against the dashboard `Env`. Schema and migrations are owned by the backend; tests apply `../backend/migrations`.

Two copies of `drizzle-orm` exist (backend's and ours). Runtime is fine; `tsconfig.json` `paths` points both at ours so the types match. Keep the versions in both `package.json` files equal.

## Tests

Vitest with `@cloudflare/vitest-plugin`, Miniflare D1. `test/helpers/session.ts` makes signed session cookies (`adminCookie()`, `userCookie()`, `sessionCookie(userId, opts)`) by writing a `sessions` row and signing the token with the test `BETTER_AUTH_SECRET`. `test/helpers/app.ts` `call(path, init, envOverrides)` counts D1 statements that run (batch items included). Outbound fetches go through MSW (`test/setup.ts`); unmocked ones return 599. `test/helpers/openrouter.ts` fakes OpenRouter `GET`/`DELETE /keys/:hash`; `giveUserData()` adds backend rows (key, storage, invite).

- `guard.test.ts` iterates every registered route: no cookie → 401 without D1, non-admin cookie → 403. New routes are covered automatically; still add success, validation, and budget tests per endpoint.
- Test bindings pin `BETTER_AUTH_URL` to the https domain so a local `.dev.vars` doesn't leak in.
