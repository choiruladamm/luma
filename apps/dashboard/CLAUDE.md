# Luma admin dashboard (Cloudflare Worker)

Admin-only Worker `luma-admin-{env}`: Hono API under `/api` on the same D1 as the backend env, behind Cloudflare Access + a second Better Auth instance (cookie sessions, Google redirect only; admins are `ADMIN_EMAILS` per env in `wrangler.jsonc`). The React SPA in `client/` is served by Workers Static Assets. Reference: `docs/dashboard.md`; read it before touching auth, middleware, or an endpoint. Client rules: `.claude/rules/dashboard-client.md`.

## Commands

- `make dashboard-test` (oxlint + Prettier check, tsc for worker + client, vitest) is the check for this app; `bun run format` fixes formatting. `make dashboard-e2e` runs Playwright against a local `e2e` env with its own seeded D1; it never touches a remote database.
- The Cloudflare env is picked by `CLOUDFLARE_ENV` at dev/build time; deploy is `make dashboard-deploy e=<env>` (flattened `dist/` config), never `wrangler deploy --env`. `wrangler secret put --env <env>` works as usual.
- Checking `luma-admin-dev` in a browser without Google: `make dashboard-dev-session` (needs `.dev.vars.remote-dev`), then `agent-browser --headers "$(cat .wrangler/dev-session/headers.json)" open <url>` and `agent-browser cookies set --curl .wrangler/dev-session/cookies.json`. Setup: `docs/dashboard.md` (Access and sessions and request guards).
- After editing `wrangler.jsonc`: `bunx wrangler types --env dev --strict-vars false` from `apps/dashboard` (needs `.dev.vars` so secrets get typed).
- Backend vars (switches, OpenRouter workspace, AI budget) come from `apps/backend/wrangler.jsonc` via `backend-vars.ts`; keep them out of this `wrangler.jsonc`.

## Lint exceptions

`.oxlintrc.json` can't hold comments, so every rule it turns off or scopes is listed here. Inline `oxlint-disable` comments carry their own reason. A new exception adds a line.

- `no-await-in-loop`, off: deliberately sequential loops.
- `typescript/consistent-return`, off: React effects return a cleanup on some paths only.
- `jsx-a11y/prefer-tag-over-role`, off: the custom combobox, listbox, option, and tablist have no native element, and swapping `role="search"`/`role="status"` would change what the tests query.
- `jsx-a11y/no-autofocus`, off: focus only moves into dialogs and search fields the user just opened.
- `react/no-array-index-key`, off: static skeleton, gap, and session lists have no stable id.
- `import/no-unassigned-import`, off: CSS and test-setup side-effect imports.
- `typescript/no-unsafe-type-assertion` and `unicorn/consistent-function-scoping`, off in `test/**` and `e2e/**`: JSON bodies, msw `params`, and small local helpers. `vitest/valid-expect` there allows `maxArgs: 2`.
- Three `jsx-a11y` click and role rules, off in `select.tsx` and `quick-search.tsx`: custom listboxes. Keyboard handling sits on the trigger or input; the options are mouse-only.
- `react/no-unstable-nested-components`, off in the two `*-table-skeleton.tsx` files: the flagged functions are `cell` renderers in column config, not components.
- Hook-dependency rules (`react-hooks/exhaustive-deps`, `react/exhaustive-effect-dependencies`, `react/memo-dependencies`, `react/set-state-in-effect`, `react/incompatible-library`, `react/immutability`), off in `app-shell.tsx` only: the route (`location.pathname`, `location.key`) is a deliberate trigger dep, so the menu closes and the header re-measures on every navigation. URL setters come from `hooks/use-search-writer.ts`, which is stable, so they belong in deps.

## Worker rules

- Middleware order: `requestId (workerApp) → securityHeaders → IP rateLimit → limitBody → [/api/auth/* allowlist → Better Auth] → requireAdmin → requireSameOriginJson → rateLimitAdmin → validate → handler`. Shared middleware, errors, and `log` come from `@luma/worker-kit` (`docs/workers.md`). `requireAdmin` is global on `/api/*`: mount every route after it, with no per-route auth.
- Build the app, middleware, and feature routers from `factory` (`env.ts`). Request schemas and response types come from `@luma/contracts/dashboard/*`; services annotate their return types with them, so `AppType` carries the contract shape and the client never hand-writes a DTO. Chain feature routes (`factory.createApp().get(...).post(...)`) and mount them with `.route()` so `AppType` carries their types.
- Features don't import each other. Each `repo.ts` function is one query-budget unit; its comment states the query count.
- Better Auth endpoints are allowlisted in `AUTH_ROUTES`; anything else under `/api/auth/*` is 404. Adding one updates `docs/dashboard.md` (Access and sessions and request guards).
- Build the Better Auth instance only inside `/api/auth/*` (tens of ms CPU). `requireAdmin` verifies the cookie HMAC itself, then one D1 join.
- Sessions slide (7 days idle) but Better Auth has no absolute limit: the 30-day cap (`SESSION_MAX_AGE_MS`) is enforced in both `requireAdmin` and the middleware in front of `get-session`. Change both together.
- Metadata only: select columns explicitly; `records`, `key_enc`, and session tokens never reach a response.
- In `db.batch`, alias every raw `sql` column (`.as("name")`): D1 names unaliased columns by their SQL text, so two identical expressions overwrite each other and come back null or shifted.
- Text search uses `instr(lower(col), term)`: D1 rejects `LIKE` patterns over 50 bytes.
- Free tier: same per-account Workers/D1 quota as the backend. Every endpoint updates the budget table in `docs/budgets.md` (Per-action budgets). No polling.

## Shared code with the backend

The D1 schema, migrations, `Db`, auth user fields, invite codes, and the OpenRouter client come from `@luma/core` (`packages/core`); tests apply its migrations. Never import from `apps/backend`. Workspace layout and the one exception (`backend-vars.ts`): `docs/workers.md`.

## Tests

- **Worker** (`test/unit`, `test/integration`): Vitest in workerd, Miniflare D1. `test/helpers/session.ts` makes signed session cookies; `test/helpers/app.ts` `call()` counts D1 statements that run with `countingD1` from `@luma/worker-kit/testing/d1`. `test/setup.ts` calls `setupWorkerTests` (unmocked outbound fetches return 599); the OpenRouter fake is `@luma/core/testing/openrouter`. `guard.test.ts` iterates every registered route (no cookie → 401 without D1, non-admin → 403). Test bindings pin `BETTER_AUTH_URL` so a local `.dev.vars` doesn't leak in.
- **Golden** (`test/golden`): every worker route's status, headers, body, D1 queries, and subrequests in `http.golden.json`. A behavior change shows up as a diff there: review it, then accept it with `bunx vitest run test/golden -u`. Worker coverage thresholds in `vitest.config.ts` only go up (rule: `docs/workers.md`, Behavior checks).
- **Client** (`test/client`, happy-dom): see `.claude/rules/dashboard-client.md`.
- **E2E** (`e2e/`): real SPA + Worker through `vite dev`, env `e2e`; `global-setup.ts` migrates, seeds (no AI keys, so ban never calls OpenRouter), and writes an admin cookie. `@phone` specs also run on a phone viewport. Browser locale is `id-ID`; `i18n.spec.ts` opts into `en-US`.

New features add worker integration tests (success, validation, budget) and client integration tests (states and actions); flows that cross screens go to e2e.
