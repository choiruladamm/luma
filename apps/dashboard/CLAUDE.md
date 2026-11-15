# Luma admin dashboard (Cloudflare Worker)

Admin-only Worker `luma-admin-{env}`: Hono API under `/api` on the same D1 as the backend env, behind Cloudflare Access + a second Better Auth instance (cookie sessions, Google redirect only). The React SPA in `client/` is served by Workers Static Assets. Full design: `docs/dashboard.md` (repo root). Read it before touching auth, middleware, or an endpoint.

## Commands

Run from the repo root:

| Command | Does |
|---|---|
| `make dashboard-install` | `bun install` |
| `make dashboard-dev` | Vite dev server running the Worker (`CLOUDFLARE_ENV=dev`), `http://localhost:5173`, shares the local D1 of `make backend-dev`. Secrets in `.dev.vars` (copy `.dev.vars.example`) |
| `make dashboard-test` | `tsc` (worker + client) + vitest: worker in workerd (backend migrations applied), client in happy-dom |
| `make dashboard-e2e` | Playwright on the installed Chrome against `vite dev` in the local `e2e` env (own D1 under `.wrangler/e2e-state`, seeded each run, test secrets in `.dev.vars.e2e`). Never touches a remote database |
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

Stack: React, React Router, TanStack Query over `hc<AppType>()`, RHF + `zod/mini`, TanStack Table, Zustand. No Axios, no React Router actions. Files are kebab-case.

- `app/routes.tsx`: every screen is `lazy`. A route `loader` only prefetches that screen's queries (`prefetch()` in `app/prefetch.ts`, the `*Query` options exported next to each hook) and returns `null`; never read loader data, the hooks own it. Tests don't register a query client, so loaders do nothing there; `test/client/helpers/render.tsx` preloads the lazy chunks.
- One-way flow: `pages → (feature hooks + queries) → api → lib/api-client`. Components only take props. `api/`, `queries/`, and `hooks/` never import another feature; a page may compose another feature's components and queries (Ringkasan shows the users table).
- UI: board "14 · Admin web" in the Stabilo canvas. Tokens live in `client/styles/app.css` (CSS variables per theme, mapped to Tailwind colors like `bg-sheet`, `text-ink2`); never hard-code a hex in a component. Shared building blocks are in `components/ui` (Button, Chip, Card/StatCard, Segmented, Dialog, DataTable, Toast, states). Icons go through `<Icon name>` (Hugeicons stroke-rounded, the app's set).
- `features/*/api/`: raw `hc` calls through `unwrap()` → data or `ApiError`; no React. `queries/`: the only place for `useQuery`/`useMutation`, keys in `query-keys.ts`. `hooks/`: client logic that never calls the API. `schemas/`: `zod/mini` for forms (full zod doubled the Users chunk), mirroring worker limits (the worker stays the authority).
- `client/` imports from `worker/` with `import type` only. Better Auth routes aren't in `AppType`; `features/auth/api` uses plain `fetch`.
- Keep the TanStack Query defaults in `app/query-client.ts` (no focus refetch, no polling): the dashboard shares the backend's free-tier quota.
- Zustand (`stores/`) holds UI state only, never API data.
- Static files don't pass through the Worker: their security and cache headers live in `public/_headers` (`/assets/*` is hashed, so immutable).
- `tsconfig.client.json` checks `client/` (DOM + JSX); `make dashboard-test` runs it. `client/lib` has unit tests in `test/unit/`.

## Shared code with the backend

Imported relatively from `../backend/src`, never copied or edited from here (`db/schema.ts`, `db/client.ts`, `auth/user-fields.ts`, `auth/invite.ts`, `clients/openrouter.ts`). Don't import backend files that touch the backend `Env` (e.g. `features/*/service.ts`): tsc checks them against the dashboard `Env`. Schema and migrations are owned by the backend; tests apply `../backend/migrations`.

Two copies of `drizzle-orm` exist (backend's and ours). Runtime is fine; `tsconfig.json` `paths` points both at ours so the types match. Keep the versions in both `package.json` files equal.

## Tests

Three layers:

- **Worker** (`test/unit`, `test/integration`, `vitest.config.ts`): Vitest with `@cloudflare/vitest-plugin`, Miniflare D1. `test/helpers/session.ts` makes signed session cookies (`adminCookie()`, `userCookie()`, `sessionCookie(userId, opts)`). `test/helpers/app.ts` `call(path, init, envOverrides)` counts D1 statements that run (batch items included). Outbound fetches go through MSW (`test/setup.ts`); unmocked ones return 599. `test/helpers/openrouter.ts` fakes OpenRouter; `giveUserData()` adds backend rows. `guard.test.ts` iterates every registered route: no cookie → 401 without D1, non-admin cookie → 403. Test bindings pin `BETTER_AUTH_URL` to the https domain so a local `.dev.vars` doesn't leak in.
- **Client** (`test/client`, `vitest.client.config.ts`, happy-dom): `unit/` for `lib`, stores, hooks, and `components/ui`; `integration/` per feature renders the whole app (`helpers/render.tsx`: memory router over the real routes, guard, shell, query client) with the API mocked by MSW (`helpers/handlers.ts`, fixtures shaped like the worker's responses). Unhandled requests fail the test. user-event stubs the clipboard: read it back with `navigator.clipboard.readText()`.
- **E2E** (`e2e/`, `playwright.config.ts`): real SPA + Worker through `vite dev`, env `e2e`. `global-setup.ts` applies the backend migrations, empties and seeds the tables (`seed.ts`, no AI keys so ban never calls OpenRouter), and writes a signed admin cookie. Specs run serially on desktop; `@phone` ones also on a phone viewport.

New features add worker integration tests (success, validation, budget) and client integration tests (states and actions); flows that cross screens go to e2e.
