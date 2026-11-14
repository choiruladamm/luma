# Luma

iOS + Android book reader (EPUB, Markdown, PDF; personal dogfooding app): tap a paragraph → Indonesian translation + meaning from an LLM, without leaving the reading page. Local-first: the on-device Drift DB is the source of truth; the backend only adds accounts, subsidized AI keys, cloud backup, and sync.

## Repo map

| Path | What | Stack | Own rules |
|---|---|---|---|
| `apps/mobile` | Flutter app | Flutter (pinned via `.fvmrc`), Riverpod 3, Drift, go_router | `apps/mobile/CLAUDE.md` |
| `apps/backend` | Cloudflare Worker API (`/v1`) | Bun + Wrangler, Hono, D1 + Drizzle, R2, Better Auth | `apps/backend/CLAUDE.md` |
| `docs/` | Product, data model, flows, one file per topic | | index: `docs/README.md` |

Commands go through the root `Makefile` (`make help`). Mobile targets are bare (`make test`, `make dev`), backend targets are prefixed `backend-*`.

## Sources of truth

- **Product, data model, flows:** `docs/`. Read the relevant file before working on any feature. `docs/ideas/` is only worked on when asked. Cite docs by file path (`docs/llm.md`), not by section number.
- **UI design:** Stabilo in Claude Design, https://claude.ai/artifact/EBwv9zJBLZQJa5WWYiaJ7F. Read the board for the screen you're building (board name is in the issue) with the Artifact tool, not WebFetch. Every screen has a light and a dark version.
- **Tasks:** GitHub issues, labeled `area:*`. One issue = one unit of work. Every dependency on the issue's **Tergantung** line must be closed first. Tick the scope checklist when done.
- **Progress and status** live in GitHub issues and parent issues, not in this file. Check the parent issue's checklist for what's left.

## Keeping docs current

- `docs/` describes how the system works now. Changing behavior a doc describes (names, routes, tables, limits, flows, copy quoted in docs) means updating that doc in the same commit.
- No progress, dates, or branch names in docs; at most one line pointing to the parent issue. Past iterations stay only where the reason still matters, marked as old ("angka lama; sekarang …").
- After touching docs or doc citations in comments, run `make docs-check`.

## Issue workflow

- Milestone `MVP` is done except dogfooding (#29).
- Outside MVP, status labels:
  - `status:ready`: clear plan; start once all dependencies are closed.
  - `status:deferred`: waiting on a trigger (the issue's **Dibuka kalau** line). Trigger happened → switch to `status:ready`.
  - `status:idea`: undecided; may be closed `wontfix`.
- New issue / idea / deferred item: create an issue with the right status label, add it to the matching parent issue, and add a `(#N)` link in the relevant doc.
- Closed/merged is not proof it works on a device. Record device checks in the issue.

## Cross-app rules

- **API contract:** request/response examples live in `apps/backend/test/fixtures/contract/` and are tested by both vitest and Dart tests. Changing an endpoint means updating the fixture, the backend, and the Dart client together.
- **Cloudflare free tier:** backend code and any client code that calls it must fit the free tier: no polling, debounce/batch, bounded retries, streamed files. Every change to how the app calls the backend updates the budget table in `docs/backend.md` (Aturan free tier).
- **Environments:** Luma Dev (`id.ruma.luma.dev`) ↔ backend env `dev` (`luma-api-dev.chrl.cloud`); Luma (`id.ruma.luma`) ↔ env `prod` (`luma-api.chrl.cloud`). Feature branches only ever touch dev; prod builds and prod deploys come from `master` only.
- **User data is never wiped** to fix a problem: on device it survives through Drift migrations, on the backend through D1 migrations.
- **Secrets:** API keys and tokens live in `flutter_secure_storage` on device and in `wrangler secret` on the backend. Never in the DB, backups, `wrangler.jsonc`, or git.

## Workflow

- Run only the checks relevant to what you changed (per-app guidance in each app's CLAUDE.md). Commit only when those checks exit 0; never chain a commit behind `grep` or `;`.
- In the hand-off, state which checks ran and whether the full suite was skipped.
- Docs, issues, and app copy are written in Indonesian; code, identifiers, and CLAUDE.md files in English.

## Code comments

- Comments explain why, not history. Which issue added the code belongs in the commit message, not the comment.
- Issue numbers in comments only for open work (`TODO(#N): ...`) or for evidence the code can't show (a spike, eval, or decision issue, e.g. `spike #34: 30/30 valid`).
- Cite a doc (`docs/<file>.md, <Section>`) only where the code follows a rule that isn't visible from the file itself. The comment must still make sense without opening the doc, and the path and section must exist.
