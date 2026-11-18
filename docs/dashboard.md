---
type: reference
purpose: Runtime behavior and API contracts for dashboard maintainers.
sections: [Runtime and environments, Access and sessions and request guards, API routes and errors, Screens and navigation, Localization]
---

# Admin dashboard

## Runtime and environments

The dashboard in `apps/dashboard` is a Worker serving a React SPA through Static Assets, with `/api/*` routed to the Worker and an SPA fallback for other paths. Dev uses `luma-admin-dev` at `luma-admin-dev.chrl.cloud`; production uses `luma-admin` at `luma-admin.chrl.cloud`. Both disable workers.dev and preview URLs and bind the backend D1 database for the corresponding environment.

`backend-vars.ts` copies the backend's feature flags, OpenRouter workspace ID and AI budget into the dashboard at build time. Local Vite serves the SPA and uses local D1 state shared with the backend; the local e2e environment has separate D1 state and reads backend dev variables. See [operations.md](operations.md) for setup and deployment, [backend.md](backend.md) for shared data and feature semantics, and [budgets.md](budgets.md) for request budgets.

## Access and sessions and request guards

Cloudflare Access protects the deployed custom domains. The dashboard also uses Google OAuth through its own Better Auth instance and signed cookie session on the shared database. Protected requests accept a dashboard cookie signed with its own secret, not a mobile bearer token, and recheck admin membership on every request; removing an email disables existing sessions. A verified email must match `ADMIN_EMAILS`, case-insensitively after trimming; an empty string permits no admins. The binding must be a string. A verified admin's first Google sign-in can create the account without a prior app sign-in or invite.

Sessions expire after seven idle days, sliding at most once per day while used, with a 30-day absolute cap from creation. The login screen copy still says 12 hours (#231). `trustedOrigins` contains `BETTER_AUTH_URL`, including localhost when configured.

`securityHeaders` wraps the chain first, followed by request ID and per-IP rate limiting. The allowlisted auth routes are `GET /api/auth/get-session`, `POST /api/auth/sign-in/social`, `GET /api/auth/callback/google`, and `POST /api/auth/sign-out`; they go to Better Auth; other `/api/auth/*` routes return 404. Protected API routes then require an admin session, require `application/json` and the configured origin on mutations (otherwise 403), and apply per-admin mutation limits. Successful admin mutations are audited. Worker responses and static assets carry CSP and `nosniff` headers.

## API routes and errors

- `GET /api/overview` returns user, storage, sync, invite, feature flag and AI spend summaries. `syncToday.rows` counts changed sync records in the current UTC day, not D1 billing telemetry; its limit is an account-level comparison. Spend covers completed UTC days in the current month within the latest 30 days, so day 1 of a 31-day month can be omitted. A missing management key skips the lookup; a failure is logged and returns null spend.
- `GET /api/users` filters by name or email search, active/banned status, AI key presence and activity (`7d`, `30d`, `never`). Sorts are `created`, `lastActive`, `r2`, `sync` and `relevance`; search defaults to relevance, otherwise creation. Creation ties use ID in the same direction; other ties use descending creation and ID. Never-active users sort last. Last active is the latest update across shared sessions, including admin sessions.
- `GET /api/users/:id` returns user detail, providers, stored invite code, up to 50 stored session rows and AI information. Sessions can be expired or represent the same device more than once. An OpenRouter usage failure leaves usage null. `POST /api/users/:id/ban` and `/unban` perform admin actions described in [backend.md](backend.md). If OpenRouter key revocation fails, ban returns 502 before any D1 mutation, though it has already read D1. Concurrent key issuance between revocation and the D1 batch can leave an upstream key orphaned until expiry.
- `GET /api/invites` filters by status, use within 7 or 30 days, and code or user email search. Sorts are `default`, `usedAt`, `createdAt` and `code`; default places newest unused first, then used by most recent use. `usedAt` determines used status even if account deletion clears `usedBy`. Missing dates sort last for date sorts. Counts follow search; total follows all filters. Legacy short codes display as stored. `POST /api/invites` creates 1–20 codes; `DELETE /api/invites/:code` deletes an unused code, returning 409 for a used code and 404 for a missing one.

Both list endpoints cap `page` at 10,000 and return at least one page even for zero results. A page beyond the end has no items. Users default to 50 items per page (maximum 50); invites default to 20 (maximum 50).

Dashboard API handler errors use `{ "error": { "code": "...", "message": "..." } }`, including `BAD_REQUEST`, `UNAUTHORIZED`, `FORBIDDEN`, `NOT_FOUND`, `INVITE_CODE_USED`, `RATE_LIMITED`, `OPENROUTER_FAILED` and `INTERNAL_ERROR`. Allowlisted Better Auth endpoints pass through Better Auth responses rather than this envelope.

Responses carry metadata only: every query selects its columns explicitly, and sync record bodies (`records`), encrypted AI keys (`key_enc`), and session tokens never reach a response.

## Screens and navigation

Routes are `/login`, `/` (overview), `/users`, `/users/:id` and `/invites`, plus a not-found screen. Overview loads recent users using the default Users query; its refresh reloads both overview and users. The protected shell loads overview for navigation counts on every screen. List filters, sorting and pagination are reflected in the URL; each list clamps an out-of-range page after a response. The DEV badge is based on hostname; there is no PROD badge.

Queries are stale after one minute by default, with no polling or focus/reconnect refetch. Server and network failures get one retry; 4xx errors and mutations do not. The session query is stale after one hour and refetches on focus. Ban and unban invalidate user lists and detail. `UNAUTHORIZED` navigates to login; a code-less 401 classified as `ACCESS_EXPIRED` reloads the page for Cloudflare Access. API and auth fetches send `X-Requested-With: XMLHttpRequest` so Cloudflare Access returns a classifiable 401. `RequireSession` redirects a successful null session to login and offers inline retry if the session check fails.

## Localization

See [i18n.md](i18n.md) for shared localization policy. Dashboard copy lives in `client/i18n/id.ts` and `client/i18n/en.ts`. A saved language choice wins; otherwise English browsers get English and others Indonesian. English loads as a separate chunk, with Indonesian shown until it is available. Formatters use the selected locale; user data is not translated.
