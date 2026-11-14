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

The Cloudflare env is picked by `CLOUDFLARE_ENV` at dev/build time, never `wrangler deploy --env`. `wrangler secret put --env <env>` still reads `wrangler.jsonc` and works as usual. After editing `wrangler.jsonc`: `bunx wrangler types --env dev --strict-vars false` from `apps/dashboard` (needs `.dev.vars` so secrets get typed).

## Code layout

```
worker/
├── index.ts       # app, middleware order, Better Auth allowlist, export AppType
├── auth.ts        # Better Auth instance + isAdmin (ADMIN_EMAILS)
├── middleware.ts  # requestId, security headers, IP rate limit, requireAdmin, mutation check
├── audit.ts       # audit(c, action, targetId) → Workers Logs; call it in every mutation
├── errors.ts      # ApiError + onError, {"error": {"code", "message"}}
├── env.ts         # AppEnv: Bindings + c.var (db, admin, requestId)
└── repo.ts        # every D1 query
```

- Middleware order: `securityHeaders → requestId → IP rateLimit → [/api/auth/* allowlist → Better Auth] → requireAdmin → requireSameOriginJson → validator → handler`. `requireAdmin` is global on `/api/*`; never add per-route auth or mount routes before it.
- New admin routes are chained onto `routes` in `index.ts` so `AppType` carries their types. Feature routes take `db`/`admin` from `c.var`.
- Better Auth endpoints are allowlisted in `AUTH_ROUTES`; anything else under `/api/auth/*` is 404. Don't add one without updating `docs/dashboard.md`.
- Never build the Better Auth instance outside `/api/auth/*` (tens of ms CPU). `requireAdmin` verifies the cookie HMAC itself, then one D1 join.
- Metadata only: never select `records`, `key_enc`, or session tokens into a response. Pick columns explicitly.
- Free tier: same per-account Workers/D1 quota as the backend. Every endpoint updates the budget table in `docs/backend.md` (Anggaran per aksi). No polling.

## Shared code with the backend

Imported relatively from `../backend/src`, never copied or edited from here (`db/schema.ts`, `db/client.ts`, `auth/user-fields.ts`). Schema and migrations are owned by the backend; tests apply `../backend/migrations`.

Two copies of `drizzle-orm` exist (backend's and ours). Runtime is fine; `tsconfig.json` `paths` points both at ours so the types match. Keep the versions in both `package.json` files equal.

## Tests

Vitest with `@cloudflare/vitest-plugin`, Miniflare D1. `test/helpers/session.ts` makes signed session cookies (`adminCookie()`, `userCookie()`, `sessionCookie(userId, opts)`) by writing a `sessions` row and signing the token with the test `BETTER_AUTH_SECRET`. `test/helpers/app.ts` `call(path, init, envOverrides)` counts D1 queries. Outbound fetches go through MSW (`test/setup.ts`); unmocked ones return 599.

- `guard.test.ts` iterates every registered route: no cookie → 401 without D1, non-admin cookie → 403. New routes are covered automatically; still add success, validation, and budget tests per endpoint.
- Test bindings pin `BETTER_AUTH_URL` to the https domain so a local `.dev.vars` doesn't leak in.
