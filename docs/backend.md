---
type: reference
purpose: Look up the mobile Worker API and the resources it owns.
sections: [Environments and bindings, Request pipeline and API conventions, Authentication and accounts, AI subsidy, Files and cloud backups, D1 schema]
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

`requestId` assigns an `x-request-id` to each request. Under `/v1/*`, `rateLimit(clientIp)` runs before `deps`, which constructs the Drizzle and OpenRouter management clients without performing I/O. Each router then applies its own guards.

| Routes | After IP limiting and dependency setup |
|---|---|
| `GET /v1/health` | Public. Returns `{status: "ok", env}`. |
| `/v1/auth/*` | Auth body limit, then the allowlisted Better Auth handler. |
| `/v1/me` | Bearer session. |
| `/v1/ai/*` | `AI_KEY_ENABLED`, then bearer session. Only `POST /key` adds a user rate limit and body limit. |
| `/v1/files/*`, `/v1/backups*` | `BACKUP_ENABLED`, bearer session, user rate limit, then any route-specific payload checks. Sync file transfers go through the same file routes. |
| `/v1/sync/*` | `SYNC_ENABLED`, bearer session, user rate limit, then sync request validation. See [Sync protocol](sync-protocol.md). |

Each feature switch enables its routes only when set to the string `"true"`. A disabled feature returns 503 `SERVICE_DISABLED` with `Retry-After` before accessing D1 or R2. The IP and user keys use the Worker rate-limit binding. Rejection returns 429 `RATE_LIMITED` with `Retry-After`.

The API uses JSON with camelCase field names and returns errors as `{error: {code, message}}`. Clients branch on the `UPPER_SNAKE_CASE` code. `normalizeAuthError` wraps Better Auth JSON errors and preserves their codes. Unknown routes return 404 `NOT_FOUND`. The app logs unexpected failures with the request ID and returns 500 `INTERNAL_ERROR`. `limitBody` applies route-specific JSON size limits before parsing and returns 413 `PAYLOAD_TOO_LARGE` when exceeded. File and snapshot bodies use the upload contract below.

## Authentication and accounts

- `AUTH_PATHS` exposes only `POST /v1/auth/{sign-up/email,sign-in/email,sign-in/social,sign-out}`. Email and password authentication is enabled outside production. Native Google sign-in sends `{provider: "google", idToken: {token}}` to `sign-in/social`. `GOOGLE_CLIENT_IDS` supplies the accepted audiences. The mobile flow uses the native ID token directly.
- When `INVITE_REQUIRED` is `"true"`, the new-user hook consumes `x-invite-code` with a conditional update on an unused code and assigns the user after creation. Missing, unknown, and consumed codes return 403 with `INVITE_CODE_REQUIRED`, `INVALID_INVITE_CODE`, and `INVITE_CODE_USED`, respectively. `normalizeInviteCode` ignores case and separators. New codes are issued as `LUMA-XXXXX-XXXXX`. Existing shorter codes still work.
- Mobile stores the `set-auth-token` response header in secure storage and sends it as `Authorization: Bearer <token>`. `requireSession` looks up the token portion before the signature in D1 via `findSessionUser`. It returns 401 `UNAUTHORIZED` for a missing or expired session. Valid sessions slide under `SESSION_EXPIRES_IN_MS` and `SESSION_UPDATE_AGE_MS` (60 days, renewed at most daily). Better Auth instances are reused per isolate while the environment object is the same.
- `GET /v1/me` returns `{user: {id, name, email, image}}`. Mobile opens from its stored token and checks this endpoint in the background. On an account switch, the app commits the new session only after confirmation and removal of the previous account’s local books and AI call history.
- `DELETE /v1/me` revokes any subsidized OpenRouter key first, then deletes objects under the user's R2 prefix. After the last page, D1 deletes the user and cascades their owned rows. `deleteAccount` processes up to `DELETE_PAGES_PER_REQUEST` pages and returns 202 `{status: "pending"}` if more remain or 200 `{status: "deleted"}` when complete. Mobile repeats pending requests up to `AuthRepository.deleteAttempts`, then reports `DELETE_PENDING`.
- Public `GET /privacy` and `GET /account/delete` serve static pages outside the versioned API and use `CONTACT_EMAIL`. Their content and `LAST_UPDATED` live in `features/legal/routes.ts`.

## AI subsidy

Mobile sends inference requests directly to OpenRouter. A user's own key takes precedence over a subsidized key and stays on the device. `AiKeyRepository` stores the subsidized key in mobile secure storage and requests it on demand. See [LLM](llm.md) for inference behavior.

| Route | Contract |
|---|---|
| `POST /v1/ai/key` | Accepts `{rotate?: boolean}` and returns `{key, expiresAt, dailyLimitUsd}`. |
| `GET /v1/ai/usage` | Returns `{dailyLimitUsd, remainingUsd, usedTodayUsd, resetsAt}`. With no issued key it returns the full configured allowance without contacting OpenRouter. `resetsAt` is the next UTC midnight. |
| `GET /v1/ai/config` | Returns `{chatModels, embeddingModels, dailyLimitUsd}` from Worker configuration. |

`issueKey` creates the key lazily in `OPENROUTER_WORKSPACE_ID` with the configured `AI_DAILY_LIMIT_USD`, a daily reset, and expiry from `AI_KEY_TTL_DAYS`. D1 stores its hash and AES-GCM-encrypted key in a single row per user. Requests reuse a decryptable key outside the `ROTATE_BEFORE_MS` window. Explicit `rotate` checks whether the upstream key still exists before replacing an otherwise reusable key. A changed daily limit is patched on the next eligible issuance request. Parallel issuance can leave an extra upstream key until expiry.

Key and usage requests return 403 `AI_BANNED` for a banned user. The dashboard ban flow revokes the upstream key before setting the ban flag and deleting the key row. Account sign-in, sync, and backup remain available. After unban, the next issuance request can create a new key.

OpenRouter enforces the per-key limit and workspace guardrails. Keep `AI_CHAT_MODELS` and `AI_EMBEDDING_MODELS` aligned with the guardrail allowlist. `AI_MONTHLY_BUDGET_USD` is a dashboard display value. See [Operations](operations.md#openrouter-workspaces) for provider-side setup.

## Files and cloud backups

Objects are scoped to the bearer user's `u/{userId}/` prefix. Book files and covers live under `files/`, and snapshot ZIPs under `backups/`. Sync shares the same file objects. See [Backup](backup.md) for the mobile ZIP format and backup and restore flow.

| Route | Contract |
|---|---|
| `POST /v1/files/missing` | Takes `{names}` with up to 1,000 entries and returns unique absent names as `{missing}`. Each call lists through the user's entire `files/` prefix in pages. |
| `PUT /v1/files/:name` | Streams a file upload and returns `{name, size}`. A name already present returns the stored size and discards the incoming body. |
| `GET /v1/files/:name` | Streams the object with `Content-Length`, or returns 404 `NOT_FOUND`. |
| `PUT /v1/backups` | Takes a ZIP stream plus an `x-backup-manifest` header containing the one-line manifest JSON. Returns `BackupInfo`. |
| `GET /v1/backups` | Returns `{backups}`, newest first, from R2 object metadata. |
| `GET /v1/backups/:id` | Streams the ZIP with `Content-Length`. An invalid or missing ID returns 404 `BACKUP_NOT_FOUND`. |

`FILE_NAME` restricts names to 1–200 ASCII letters, digits, dots, underscores, or hyphens. Both upload routes require a nonnegative integer `Content-Length` up to `MAX_UPLOAD_BYTES` (100 MiB). The Worker pipes the body through `FixedLengthStream` to R2. An invalid length returns 400 `BAD_REQUEST`, and a length above the cap returns 413 `PAYLOAD_TOO_LARGE`.

`reserveBytes` conditionally increments the user's R2 usage in D1 before a new upload, against `USER_STORAGE_BYTES`. A failed reservation returns 413 `STORAGE_FULL`. A failed upload releases the reservation. The backup route reserves before pruning. It derives the ZIP ID from the current UTC time (`yyyyMMddTHHmmssZ`), stores manifest fields as R2 metadata, and keeps the latest `BACKUP_RETENTION` snapshots, subtracting the bytes freed by pruning. Uploads in the same second share an object key and can overcount usage. `BackupInfo` contains `id`, `createdAt`, `size`, `books`, `aiResults`, `schemaVersion`, and `appVersion`.

## D1 schema

| Source | Ownership and relationships |
|---|---|
| [auth-schema.ts](../apps/backend/src/db/auth-schema.ts) | `users` owns `sessions` and linked provider `accounts`. Both cascade on user deletion. `verifications` is a separate Better Auth table. |
| [schema.ts](../apps/backend/src/db/schema.ts) | Each user owns zero or one `ai_keys` row, zero or one lazily created `user_storage` row, and any number of sync `records`. These cascade on user deletion. `invite_codes.used_by` is nullable and cleared on user deletion, with `used_at` retained. |

The linked schema files define columns and indexes. See [Sync protocol](sync-protocol.md#records-and-keys) for the record identity and cursor, and [Per-action budgets](budgets.md#per-action-budgets) for access costs.
