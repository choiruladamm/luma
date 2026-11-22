---
type: reference
purpose: Look up the free-tier constraints and request budgets for the mobile API and admin dashboard.
sections: [Free-tier limits, Server request policy, Client request policy, Per-action budgets, Monitoring signals]
---

# Request budgets

## Free-tier limits

Both Workers draw from the same Cloudflare account's free-tier allowances. Dashboard API requests count toward the Worker allowance. Dashboard assets served without invoking the Worker are outside that allowance.

| Resource | Free-tier allowance |
|---|---|
| Workers | 100,000 requests per UTC day, 10 ms CPU and 50 external subrequests per invocation. [Workers limits](https://developers.cloudflare.com/workers/platform/limits/) |
| D1 | 5 million rows read and 100,000 rows written per UTC day. Storage is limited to 500 MB per database and 5 GB per account. Free Workers can make 50 D1 queries per invocation, and statements can bind up to 100 parameters each. A D1 batch counts as one query for the invocation limit. [D1 pricing](https://developers.cloudflare.com/d1/platform/pricing/) · [D1 limits](https://developers.cloudflare.com/d1/platform/limits/) |
| R2 Standard | 10 GB-month of storage, 1 million Class A operations, and 10 million Class B operations per month. LIST and PUT are Class A. HEAD and GET are Class B. DELETE is free for billing purposes. [R2 pricing](https://developers.cloudflare.com/r2/pricing/) |

Measure Worker invocations, SQL statements, D1 rows read and written, R2 calls, and outbound HTTP separately. D1 bills rows scanned and mutations, including index maintenance. Statement counts and response sizes alone cannot predict billed rows.

## Server request policy

- Keep CPU bounded. Stream uploads and downloads through R2 and enforce body size before JSON parsing. Sync pull formats records in SQL, with the key names of the request's API version, so no version re-encodes it, and sync push packs keys and changed records into JSON inputs to stay within D1's parameter limit.
- Bound work per invocation. Batch related writes and multi-object deletes. Use indexed lookups for cursor pages, and skip sync record writes when the merged data is unchanged. List and aggregate queries can scan more rows than they return.
- Keep request-path cost controls in place. The [Worker pipeline](backend.md#request-pipeline-and-api-conventions) applies IP limits and feature-specific guards. R2 [storage limits](backend.md#files-and-cloud-backups) and [sync quotas](sync-protocol.md#sync-quotas-and-compatibility) constrain individual users. Dashboard IP limiting applies to API routes, with `rateLimitAdmin` adding a per-admin limiter on mutations. Cloudflare Access gates dashboard traffic at the edge.
- Update the relevant budget when an endpoint or client call pattern changes.

## Client request policy

### Mobile

- Drive calls from lifecycle, local changes, or user actions. `SyncTrigger` runs full sync on sign-in or startup with a stored session, and on resume subject to `SyncRepository.resumeGap`. Local changes trigger push only after `SyncTrigger.debounce`. The outbox deduplicates by record key. `CloudBackupService.missingBatch` bounds the number of names in each missing-file check.
- `UsageRepository.sendIfDue` sends the usage rollup at most once per local day, in requests of up to `UsageService.maxRows` rows; usually one request a day. A failure waits for the next day.
- `CloudBackupRepository.autoInterval` determines when an automatic backup is due. `retryGap` spaces automatic attempts even after failure. See [Backup](backup.md) for the mobile flow.
- `BackendClient` uses exponential backoff up to `backendMaxAttempts` (three attempts including the original) for eligible network failures and 5xx responses without `Retry-After`. Sign-in and sign-up opt out. Sync records a pause for future push or pull when it receives an error with `Retry-After`. Cloud backup waits inline on `RATE_LIMITED` for both file and snapshot PUTs, up to `rateLimitRetries`, using `Retry-After` or a one-minute fallback.
- AI config is cached for its provider's lifetime. Usage is fetched on demand with a one-hour cache and a forced refresh path. `AiKeyRepository` reuses the stored key until rejected or within `refreshBefore` of expiry.

### Dashboard

- The dashboard uses event-driven queries. `createQueryClient` turns off focus and reconnect refetch by default. Queries use a 60-second stale window and up to one retry for non-4xx failures. Mutations have no automatic retry. The session query opts into focus refetch once stale, with a one-hour stale window.
- A cold Overview load starts three API requests through the loaders in `client/app/routes.tsx`. These fetch the session, overview, and default Users page for recent users. Other protected screens also load session and overview for the shell, plus their own page query. A fresh cache can satisfy those reads. Overview's manual refresh refetches overview and recent users.
- Users and invite searches debounce input by 300 ms. Header quick search requires at least two characters. Filters, sorting, and pagination load the corresponding query key. Ban and unban invalidate user lists and detail. Invite mutations invalidate invite queries.

## Per-action budgets

Counts describe typical completed requests and exclude client retries. Each route invocation counts as one Worker request. Table entries add feature costs to the applicable session cost unless a test total is given. Budget tests count the SQL statements that run (each statement in a batch counts) and HTTP fetches. R2 operations are counted separately. Each Worker's golden test records the exact counts of every route's success and of the error cases it exercises (missing or bad session, invalid or oversized body, switch off, rate limit) in `http.golden.json`, so a change in any recorded count shows up in review.

### Mobile API

Every row below applies to both `/v1/*` and `/v2/*`: the routers, guards, and D1 and R2 counts are the same, and the golden files record identical counts for both (usage upload is recorded only in `http.v2.golden.json`, so the `/v1` file stays unchanged). The one difference is CPU on `/v1`: the temporary [case adapter](backend.md#api-versions) converts a request's JSON keys after the single parse `validate` already does (never a second parse or a stringify, and `records.*.data` is not walked), and converts a small 2xx JSON response by parsing and stringifying it. Sync pull is never parsed or re-encoded on either version.

| Action | D1 statements | R2 and outbound HTTP |
|---|---|---|
| Health | 0 | None (`health.test.ts`). |
| Native Google sign-up | At most 8 with an invite in `auth-google.test.ts`. Returning sign-in skips invite consumption and new-user creation. | One JWKS fetch in the fixture. |
| Email auth outside prod | Sign-in at most 4 in `auth.test.ts`. Sign-up uses the creation path and the invite hooks when enabled. | None. |
| Bearer session and `GET /v2/me` (and `/v1/me`) | `findSessionUser` uses one join for a token and one UPDATE when renewal is due. `account.test.ts` allows at most 2 for `GET /v1/me`. | None. |
| Account deletion | `revokeKey` adds a key lookup on every attempt. `deleteUser` adds a DELETE on completion, with cascades. | One key delete if a key row exists, then at most `DELETE_PAGES_PER_REQUEST` R2 LISTs and one bulk DELETE per nonempty page. |
| AI config or usage | Config uses the session alone. `usage` adds one lookup via `findUserKey`. | Config has no fetch. Usage gets upstream usage only when a key exists. |
| AI key | `issueKey` adds one lookup and one write if creating, rotating, or updating the limit. `ai-key.test.ts` asserts at most 2 total statements for reuse and at most 3 for creation in its fixtures. | Fresh reuse costs 0 fetches, creation 1. A limit patch or existence check each adds 1. Replacement costs 2 (delete and create), or 3 if an existence check led to it. |
| Missing-file check | Session only. `backup.test.ts` checks at most one statement for a fresh session. | `missingFiles` uses one LIST per R2 page. Each client chunk can traverse several pages. |
| File PUT | `putFile` adds one reservation for a new object, with a compensating write if upload fails after reservation. `backup.test.ts` allows at most three total statements for a successful upload. | One HEAD, plus one PUT if absent. |
| Snapshot PUT | `putBackup` adds one reservation plus one write if pruning frees bytes. A failed upload after reservation releases those bytes. `backup.test.ts` allows at most three total statements for a successful upload without pruning. | One PUT and one LIST, with one bulk DELETE if pruning. |
| Cloud restore | Each request pays the bearer session cost. | One LIST to choose a snapshot, one GET for the ZIP, and one GET per needed book or cover missing locally. |
| Sync push | `findRecords` and `syncUsage` add one read statement each. `writeRecords` adds a two-statement batch if records changed. `sync.test.ts` allows 6 total with session renewal. | No R2 or HTTP in the push endpoint. Separate book-file checks and uploads use the file API costs above. |
| Usage upload | `usageQuota` adds one read. `writeUsage` adds a two-statement batch: the quota update and one upsert of up to 500 rows (one D1 row written per row). `usage.test.ts` allows 5 total with session renewal. The app sends at most once per user per day. | None. |
| Sync pull and book downloads | `pullRows` adds one indexed statement per page with up to `limit + 1` result rows. `sync-pull.test.ts` allows 3 total with renewal. Each download pays its own session cost. | No R2 or HTTP in pull. A missing book download uses one GET for the source file or Markdown dump. |

A backup run makes one missing-file request per name chunk, one PUT per absent object, and one snapshot PUT. Sync can make up to `SyncRepository.maxBatches` push requests or pull pages per phase, plus file calls. The application sync counter counts changed records. It omits D1 index writes and the usage-row update.

### Dashboard

`requireAdmin` costs one session/user join with a signed cookie, plus a DELETE if the session reaches its absolute cap while still within idle expiry. A missing or invalid signature short-circuits before querying D1. Protected feature costs below are additional to that join. The auth routes use their own session handling.

| Action | D1 statements | Outbound HTTP |
|---|---|---|
| Google login start and callback | Start costs 0 with cookie OAuth state. The callback test in `login.test.ts` allows at most 5 for an existing account. New admin login also creates a user and provider account. | Callback exchanges the Google authorization code for tokens. |
| Get session | With a signed cookie, `endSessionIfPastMaxAge` runs one conditional DELETE, then Better Auth looks up the session and can renew it with one UPDATE when due. | None. |
| Overview | `overviewCounts` adds three aggregate statements over users, storage, and unused invites. `overview.test.ts` checks four total. | `getOverview` makes one OpenRouter activity call when the management key is set. |
| User list | `listUsers` adds two batched statements for page and total. Search, filters, sorting, and offset affect rows scanned. | None. |
| User detail | `findUserDetail` adds five batched statements for user, sessions, key, invite, and providers. `users.test.ts` checks six total. | One key usage call when the user has a key. |
| Ban and unban | Ban adds one key lookup and a two-statement `banUser` batch. `users.test.ts` checks four total. Unban adds one UPDATE. | Ban deletes the OpenRouter key if one exists. |
| Invite list | `listInvites` adds two batched statements for page and counts. | None. |
| Create and delete invites | `insertInvites` inserts 1–20 rows in one statement. `deleteUnusedInvite` issues one DELETE, adding one read via `inviteExists` when no row was deleted. | None. |

## Monitoring signals

- Check Worker request volume, p99 CPU, and error rates by environment after a release. Use the response's request ID to correlate failures with Workers Logs. Investigate p99 CPU above 5 ms, error 1027, or account traffic above 50,000 requests per UTC day.
- Track D1 row reads and writes in Row Metrics or statement metadata. Watch aggregate dashboard reads and sync writes separately. The dashboard's sync count sums app-level record writes for the environment and is a partial view of account-wide D1 consumption.
- Track R2 stored bytes and operation classes against their monthly allowances. Compare dashboard OpenRouter spend with the configured budget and check logs when the usage call fails.
