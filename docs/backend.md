---
type: reference
purpose: Look up the mobile Worker API and the resources it owns.
sections: [Environments and bindings, Request pipeline and API conventions, API versions, Authentication and accounts, AI subsidy, Usage analytics, Files and cloud backups, D1 schema]
---

# Backend API

## Environments and bindings

The Hono Worker runs on workerd. Its entry point is `apps/backend/src/index.ts`, and `app.ts` mounts the feature routers. Bun is used for tooling.

| Environment | Worker | Mobile API origin | D1 and R2 resource names |
|---|---|---|---|
| dev | `luma-backend-dev` | `https://luma-api-dev.chrl.cloud` | `luma-dev` |
| prod | `luma-backend` | `https://luma-api.chrl.cloud` | `luma-prod` |

`apps/backend/wrangler.jsonc` declares each environment's `DB` (D1), `BUCKET` (R2), `RATE_LIMITER`, and feature variables. Both API environments also enable the `workers.dev` endpoint. Mobile selects the origin via `backendUrls` in `backend_client.dart`, with `BACKEND_URL` as an override. The dashboard shares its environment's D1 database. See [Operations](operations.md) for provisioning.

## Request pipeline and API conventions

`requestId` assigns an `x-request-id` to each request. Under `/v1/*` and `/v2/*` (same routers, [API versions](#api-versions)), `rateLimit(clientIp)` runs before `deps`, which constructs the Drizzle and OpenRouter management clients without performing I/O. Each router then applies its own guards.

| Routes | After IP limiting and dependency setup |
|---|---|
| `GET /v2/health` | Public. Returns `{status: "ok", env}`. |
| `/v2/auth/*` | Auth body limit, then the allowlisted Better Auth handler. |
| `/v2/me` | Bearer session. |
| `/v2/ai/*` | `AI_KEY_ENABLED`, then bearer session. Only `POST /key` adds a user rate limit and body limit. |
| `/v2/files/*`, `/v2/backups*` | `BACKUP_ENABLED`, bearer session, user rate limit, then any route-specific payload checks. Sync file transfers go through the same file routes. |
| `/v2/sync/*` | `SYNC_ENABLED`, bearer session, user rate limit, then sync request validation. See [Sync protocol](sync-protocol.md). |
| `POST /v2/usage` | Bearer session, user rate limit, body limit, then the usage checks in [Usage analytics](#usage-analytics). No feature switch. |

Each feature switch enables its routes only when set to the string `"true"`. A disabled feature returns 503 `SERVICE_DISABLED` with `Retry-After` before accessing D1 or R2. The IP and user keys use the Worker rate-limit binding. Rejection returns 429 `RATE_LIMITED` with `Retry-After`.

The routes below are written as `/v2/...`; each is also served at `/v1/...` until #265 removes it. The API uses JSON, with snake_case field names on `/v2` and camelCase on `/v1`, and returns errors as `{error: {code, message}}`. Clients branch on the `UPPER_SNAKE_CASE` code. `normalizeAuthError` wraps Better Auth JSON errors and preserves their codes. Unknown routes return 404 `NOT_FOUND`. The app logs unexpected failures with the request ID and returns 500 `INTERNAL_ERROR`. `limitBody` applies route-specific JSON size limits before parsing and returns 413 `PAYLOAD_TOO_LARGE` when exceeded. File and snapshot bodies use the upload contract below.

## API versions

`app.ts` mounts every router twice, in the same order and with the same guards, rate-limit keys, and kill switches: `/v2/*` is the API, and `/v1/*` is the same routers behind an adapter. `wire(version)` sets `c.var.wire` first, so routes and the adapter know which version a request came in on.

- **`/v2`** speaks the contracts in `@luma/contracts/backend/*` natively: snake_case keys, the same as the DTO types, and services return those objects. Drizzle and domain code stay camelCase; they map at the boundary.
- **`/v1`** answers exactly as before, camelCase, for app installs older than the move to `/v2` (the current app calls `/v2` through `BackendClient.apiPrefix`). `v1Adapter` (`middleware/v1-adapter.ts`) is temporary and goes away with `/v1` (#265). A request's JSON body is parsed once, lazily where `validate` reads it (after `limitBody`), and converted to snake_case; a 2xx JSON response is converted to camelCase. It skips error bodies (identical on both versions), non-JSON responses (ZIPs, files), and `/v1/auth/*`.
- **Sync pull is never re-encoded.** Its body is built by SQL and string concatenation (see [Sync protocol](sync-protocol.md)), so `pullRows` and `pull` write the keys of the request's version directly and mark the response `wireDone`, which the adapter leaves alone.
- **Opaque payloads keep their casing on both versions:** sync `records[].data` (Drift's JSON) and the `x-backup-manifest` header (the backup ZIP's own `manifest.json`). The adapter's request conversion skips `records.*.data`. Error bodies `{error: {code, message}}` are the same on both.
- **Better Auth** answers camelCase and its `basePath` stays `/v1/auth`. `/v1/auth/*` passes through unchanged. `/v2/auth/*` rewrites the request to that base path, converts the JSON body's keys to camelCase (`id_token` → `idToken`), and converts the JSON response with `snakeJson` after `normalizeAuthError`. Headers (`x-invite-code`, `set-auth-token`) are unchanged.
- **Field names in messages** follow the version: the sync push 400 reads `Body must be {"schemaVersion", "records": [≤500]}` on `/v1` and `{"schema_version", ...}` on `/v2` (`validate` takes a message function). Other messages name no multi-word field.

Contract fixtures: `packages/contracts/fixtures/v1/` stays as the app installs see it, and `fixtures/v2/` holds the snake_case equivalents; the contracts' tests check that snake_case of each v1 fixture is its v2 fixture. The golden files `http.golden.json` (`/v1`) and `http.v2.golden.json` record one scenario on both prefixes with identical statuses and D1 counts.

## Authentication and accounts

- `AUTH_PATHS` exposes only `POST /v2/auth/{sign-up/email,sign-in/email,sign-in/social,sign-out}` (and the same under `/v1/auth`). Email and password authentication is enabled outside production. Native Google sign-in sends `{provider: "google", id_token: {token}}` (`idToken` on `/v1`) to `sign-in/social`. `GOOGLE_CLIENT_IDS` supplies the accepted audiences. The mobile flow uses the native ID token directly.
- When `INVITE_REQUIRED` is `"true"`, the new-user hook consumes `x-invite-code` with a conditional update on an unused code and assigns the user after creation. Missing, unknown, and consumed codes return 403 with `INVITE_CODE_REQUIRED`, `INVALID_INVITE_CODE`, and `INVITE_CODE_USED`, respectively. `normalizeInviteCode` ignores case and separators. New codes are issued as `LUMA-XXXXX-XXXXX`. Existing shorter codes still work.
- Mobile stores the `set-auth-token` response header in secure storage and sends it as `Authorization: Bearer <token>`. `requireSession` looks up the token portion before the signature in D1 via `findSessionUser`. It returns 401 `UNAUTHORIZED` for a missing or expired session. Valid sessions slide under `SESSION_EXPIRES_IN_MS` and `SESSION_UPDATE_AGE_MS` (60 days, renewed at most daily). Better Auth instances are reused per isolate while the environment object is the same.
- `GET /v2/me` returns `{user: {id, name, email, image}}`. Mobile opens from its stored token and checks this endpoint in the background. On an account switch, the app commits the new session only after confirmation and removal of the previous account’s local books and AI call history.
- `DELETE /v2/me` revokes any subsidized OpenRouter key first, then deletes objects under the user's R2 prefix. After the last page, D1 deletes the user and cascades their owned rows. `deleteAccount` processes up to `DELETE_PAGES_PER_REQUEST` pages and returns 202 `{status: "pending"}` if more remain or 200 `{status: "deleted"}` when complete. Mobile repeats pending requests up to `AuthRepository.deleteAttempts`, then reports `DELETE_PENDING`.
- Public `GET /privacy` and `GET /account/delete` serve static pages outside the versioned API and use `CONTACT_EMAIL`. Their content and `LAST_UPDATED` live in `features/legal/routes.ts`.

## AI subsidy

Mobile sends inference requests directly to OpenRouter. A user's own key takes precedence over a subsidized key and stays on the device. `AiKeyRepository` stores the subsidized key in mobile secure storage and requests it on demand. See [LLM](llm.md) for inference behavior.

| Route | Contract |
|---|---|
| `POST /v2/ai/key` | Accepts `{rotate?: boolean}` and returns `{key, expires_at, daily_limit_usd}`. |
| `GET /v2/ai/usage` | Returns `{daily_limit_usd, remaining_usd, used_today_usd, resets_at}`. With no issued key it returns the full configured allowance without contacting OpenRouter. `resets_at` is the next UTC midnight. |
| `GET /v2/ai/config` | Returns `{chat_models, embedding_models, daily_limit_usd}` from Worker configuration. |

`issueKey` creates the key lazily in `OPENROUTER_WORKSPACE_ID` with the configured `AI_DAILY_LIMIT_USD`, a daily reset, and expiry from `AI_KEY_TTL_DAYS`. D1 stores its hash and AES-GCM-encrypted key in a single row per user. Requests reuse a decryptable key outside the `ROTATE_BEFORE_MS` window. Explicit `rotate` checks whether the upstream key still exists before replacing an otherwise reusable key. A changed daily limit is patched on the next eligible issuance request. Parallel issuance can leave an extra upstream key until expiry.

Key and usage requests return 403 `AI_BANNED` for a banned user. The dashboard ban flow revokes the upstream key before setting the ban flag and deleting the key row. Account sign-in, sync, and backup remain available. After unban, the next issuance request can create a new key.

OpenRouter enforces the per-key limit and workspace guardrails. Keep `AI_CHAT_MODELS` and `AI_EMBEDDING_MODELS` aligned with the guardrail allowlist. `AI_MONTHLY_BUDGET_USD` is a dashboard display value. See [Operations](operations.md#openrouter-workspaces) for provider-side setup.

## Usage analytics

The app sends a daily rollup of its own usage so the dashboard can show AI usage and reading per user, including calls paid with the user's own key, which OpenRouter can't see. Sending is automatic for signed-in users and independent of sync.

| Route | Contract |
|---|---|
| `POST /v2/usage` | Takes `{rows}` with 1–`MAX_USAGE_ROWS` (500) rows and returns `{applied}`. |

A row is one local `day` (`YYYY-MM-DD`) × `feature` (`group`, `breakdown`, `chat`, or `reading`) × `model` × `book_key` × `key_source` (`own`, `subsidy`), with `book_title`, `calls`, `failed`, `prompt_tokens`, `completion_tokens`, `cost_usd` (null when no call reported a cost), and `reading_seconds`. An empty string means "none" in the key fields: reading rows have no model or key source. Each row is upserted into `usage_daily`: a resent row replaces the stored one instead of adding to it, so resending a day is safe, and a key repeated within one batch keeps its last row. Cost is the client's own report, for display only; OpenRouter's per-key limit still enforces the subsidy.

A day more than one day ahead of the UTC date (the app's local day can be up to UTC+14) returns 400 `BAD_REQUEST`. Each user may write `USAGE_DAILY_ROWS` (2,000) rows per UTC day, counted in `user_storage.usage_rows`. A batch that would exceed it returns 429 `QUOTA_EXCEEDED` with `Retry-After` until UTC midnight and writes nothing. Rows are kept until the account is deleted.

## Files and cloud backups

Objects are scoped to the bearer user's `u/{userId}/` prefix. Book files and covers live under `files/`, and snapshot ZIPs under `backups/`. Sync shares the same file objects. See [Backup](backup.md) for the mobile ZIP format and backup and restore flow.

| Route | Contract |
|---|---|
| `POST /v2/files/missing` | Takes `{names}` with up to 1,000 entries and returns unique absent names as `{missing}`. Each call lists through the user's entire `files/` prefix in pages. |
| `PUT /v2/files/:name` | Streams a file upload and returns `{name, size}`. A name already present returns the stored size and discards the incoming body. |
| `GET /v2/files/:name` | Streams the object with `Content-Length`, or returns 404 `NOT_FOUND`. |
| `PUT /v2/backups` | Takes a ZIP stream plus an `x-backup-manifest` header containing the one-line manifest JSON. Returns `BackupInfo`. |
| `GET /v2/backups` | Returns `{backups}`, newest first, from R2 object metadata. |
| `GET /v2/backups/:id` | Streams the ZIP with `Content-Length`. An invalid or missing ID returns 404 `BACKUP_NOT_FOUND`. |

`FILE_NAME` restricts names to 1–200 ASCII letters, digits, dots, underscores, or hyphens. Both upload routes require a nonnegative integer `Content-Length` up to `MAX_UPLOAD_BYTES` (100 MiB). The Worker pipes the body through `FixedLengthStream` to R2. An invalid length returns 400 `BAD_REQUEST`, and a length above the cap returns 413 `PAYLOAD_TOO_LARGE`.

`reserveBytes` conditionally increments the user's R2 usage in D1 before a new upload, against `USER_STORAGE_BYTES`. A failed reservation returns 413 `STORAGE_FULL`. A failed upload releases the reservation. The backup route reserves before pruning. It derives the ZIP ID from the current UTC time (`yyyyMMddTHHmmssZ`), stores manifest fields as R2 metadata, and keeps the latest `BACKUP_RETENTION` snapshots, subtracting the bytes freed by pruning. Uploads in the same second share an object key and can overcount usage. `BackupInfo` contains `id`, `created_at`, `size`, `books`, `ai_results`, `schema_version`, and `app_version` (camelCase on `/v1`); the manifest header keeps its own camelCase keys.

## D1 schema

| Source | Ownership and relationships |
|---|---|
| [auth-schema.ts](../packages/core/src/db/auth-schema.ts) | `users` owns `sessions` and linked provider `accounts`. Both cascade on user deletion. `verifications` is a separate Better Auth table. |
| [schema.ts](../packages/core/src/db/schema.ts) | Each user owns zero or one `ai_keys` row, zero or one lazily created `user_storage` row, any number of sync `records`, and any number of `usage_daily` rows. These cascade on user deletion. `invite_codes.used_by` is nullable and cleared on user deletion, with `used_at` retained. |

The linked schema files define columns and indexes. See [Sync protocol](sync-protocol.md#records-and-keys) for the record identity and cursor, and [Per-action budgets](budgets.md#per-action-budgets) for access costs.
