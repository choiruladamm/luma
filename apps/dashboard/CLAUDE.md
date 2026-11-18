# Luma admin dashboard (Cloudflare Worker)

Admin-only Worker `luma-admin-{env}`: Hono API under `/api` on the same D1 as the backend env, behind Cloudflare Access + a second Better Auth instance (cookie sessions, Google redirect only; admins are `ADMIN_EMAILS` per env in `wrangler.jsonc`). The React SPA in `client/` is served by Workers Static Assets. Reference: `docs/dashboard.md`; read it before touching auth, middleware, or an endpoint. Client rules: `.claude/rules/dashboard-client.md`.

## Commands

- `make dashboard-test` (oxlint + Prettier check, tsc for worker + client, vitest) is the check for this app; `bun run format` fixes formatting. `make dashboard-e2e` runs Playwright against a local `e2e` env with its own seeded D1; it never touches a remote database.
- The Cloudflare env is picked by `CLOUDFLARE_ENV` at dev/build time; deploy is `make dashboard-deploy e=<env>` (flattened `dist/` config), never `wrangler deploy --env`. `wrangler secret put --env <env>` works as usual.
- After editing `wrangler.jsonc`: `bunx wrangler types --env dev --strict-vars false` from `apps/dashboard` (needs `.dev.vars` so secrets get typed).
- Backend vars (switches, OpenRouter workspace, AI budget) come from `apps/backend/wrangler.jsonc` via `backend-vars.ts`; keep them out of this `wrangler.jsonc`.

## Worker rules

- Middleware order: `securityHeaders → requestId → IP rateLimit → [/api/auth/* allowlist → Better Auth] → requireAdmin → requireSameOriginJson → rateLimitAdmin → validate → handler`. `requireAdmin` is global on `/api/*`: mount every route after it, with no per-route auth.
- Build the app, middleware, and feature routers from `factory` (`env.ts`). Chain feature routes (`factory.createApp().get(...).post(...)`) and mount them with `.route()` so `AppType` carries their types.
- Features don't import each other. Each `repo.ts` function is one query-budget unit; its comment states the query count.
- Better Auth endpoints are allowlisted in `AUTH_ROUTES`; anything else under `/api/auth/*` is 404. Adding one updates `docs/dashboard.md` (Access and sessions and request guards).
- Build the Better Auth instance only inside `/api/auth/*` (tens of ms CPU). `requireAdmin` verifies the cookie HMAC itself, then one D1 join.
- Sessions slide (7 days idle) but Better Auth has no absolute limit: the 30-day cap (`SESSION_MAX_AGE_MS`) is enforced in both `requireAdmin` and the middleware in front of `get-session`. Change both together.
- Metadata only: select columns explicitly; `records`, `key_enc`, and session tokens never reach a response.
- In `db.batch`, alias every raw `sql` column (`.as("name")`): D1 names unaliased columns by their SQL text, so two identical expressions overwrite each other and come back null or shifted.
- Text search uses `instr(lower(col), term)`: D1 rejects `LIKE` patterns over 50 bytes.
- Free tier: same per-account Workers/D1 quota as the backend. Every endpoint updates the budget table in `docs/budgets.md` (Per-action budgets). No polling.

## Shared code with the backend

Imported relatively from `../backend/src`, never copied or edited from here. Import only backend files free of the backend `Env` (not `features/*/service.ts`): tsc checks them against the dashboard `Env`. Schema and migrations are owned by the backend; tests apply `../backend/migrations`.

Two copies of `drizzle-orm` exist (backend's and ours); `tsconfig.worker.json` `paths` points both at ours so the types match. Keep the versions in both `package.json` files equal.

## Tests

- **Worker** (`test/unit`, `test/integration`): Vitest in workerd, Miniflare D1. `test/helpers/session.ts` makes signed session cookies; `test/helpers/app.ts` `call()` counts D1 statements that run. Unmocked outbound fetches return 599. `guard.test.ts` iterates every registered route (no cookie → 401 without D1, non-admin → 403). Test bindings pin `BETTER_AUTH_URL` so a local `.dev.vars` doesn't leak in.
- **Client** (`test/client`, happy-dom): see `.claude/rules/dashboard-client.md`.
- **E2E** (`e2e/`): real SPA + Worker through `vite dev`, env `e2e`; `global-setup.ts` migrates, seeds (no AI keys, so ban never calls OpenRouter), and writes an admin cookie. `@phone` specs also run on a phone viewport. Browser locale is `id-ID`; `i18n.spec.ts` opts into `en-US`.

New features add worker integration tests (success, validation, budget) and client integration tests (states and actions); flows that cross screens go to e2e.
