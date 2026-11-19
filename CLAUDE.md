# Luma

iOS + Android book reader (EPUB, Markdown, PDF; personal dogfooding app): tap a paragraph → Indonesian translation + meaning from an LLM, without leaving the reading page. Local-first: the on-device Drift DB is the source of truth; the backend only adds accounts, subsidized AI keys, cloud backup, and sync.

Apps: `apps/mobile` (Flutter), `apps/backend` (Cloudflare Worker API), `apps/dashboard` (admin Worker on the backend's D1). Each has its own CLAUDE.md. The Workers form one bun workspace with shared config at the root (`docs/workers.md`).

## Sources of truth

- **Product, data model, flows:** `docs/` (index `docs/README.md`). Read the doc for a feature before working on it. `docs/ideas/` only when asked. Cite docs by file path (`docs/llm.md`), not section number.
- **UI design:** Stabilo in Claude Design, https://claude.ai/artifact/EBwv9zJBLZQJa5WWYiaJ7F. Read the board named in the issue with the Artifact tool. Every screen has a light and a dark version.
- **Tasks and progress:** GitHub issues labeled `area:*`; one issue = one unit of work. Status lives in issues and the parent issue's checklist.

## Commands

Root `Makefile` (`make help`): mobile targets bare (`make test`), backend `backend-*`, dashboard `dashboard-*`; `make install` installs the JS workspace.

- Run only the checks for what you changed (see each app's CLAUDE.md). Commit only after they exit 0, as its own command, never chained behind `grep` or `;`.
- The hand-off states which checks ran and whether the full suite was skipped.
- After touching `docs/` or doc citations in comments: `make docs-check`.
- `scripts/hygiene` (`make hygiene`) runs the docs and comment checks plus every app's linter. It is the pre-commit hook (`make setup` once per clone) and the CI gate (`.github/workflows/ci.yml`, which also runs every app's tests).

## Issues

- Start an issue only when every dependency on its **Depends on** line is closed. Tick its scope checklist when done.
- Milestone `MVP` is done except dogfooding (#29). Outside MVP, status labels:
  - `status:ready`: clear plan; start once dependencies are closed.
  - `status:deferred`: waiting on its **Opens when** trigger. Trigger happened → `status:ready`.
  - `status:idea`: undecided; may be closed `wontfix`.
- New issue, idea, or deferred item: create it with a status label, add it to its parent issue, add a `(#N)` link in the relevant doc.
- Closed/merged doesn't prove it works on a device. Record device checks in the issue.

## Cross-app rules

- **Environments:** Luma Dev (`id.ruma.luma.dev`) ↔ backend env `dev` (`luma-api-dev.chrl.cloud`); Luma (`id.ruma.luma`) ↔ env `prod` (`luma-api.chrl.cloud`). Feature PRs merge into `dev`, which auto-deploys env `dev`; release PRs (`dev` → `master`) and hotfix PRs merge into `master`, which auto-deploys `prod` (`docs/operations.md`). Prod mobile builds and manual deploys or migrations come from `master` only.
- **User data survives every fix:** through Drift migrations on device and D1 migrations on the backend.
- **API contract:** request/response examples in `packages/contracts/fixtures/v1/`, tested by both vitest and Dart, with the zod schemas next to them in `packages/contracts`. An endpoint change updates the fixture, the backend, and the Dart client together.
- **Cloudflare free tier:** backend code and client code that calls it fit the free tier: no polling, debounce/batch, bounded retries, streamed files. Every change to how the app calls the backend updates the budget table in `docs/budgets.md` (Per-action budgets).
- **Secrets:** plaintext API keys and tokens live only in `flutter_secure_storage` (device) and `wrangler secret` (backend). Never in the Drift DB, backups, `wrangler.jsonc`, or git. (The backend keeps users' AI keys AES-GCM encrypted in D1.)

## Docs and language

- `docs/` describes how the system works now. A behavior change that a doc describes (names, routes, tables, limits, flows, quoted copy) updates that doc in the same commit. Structure and placement rules: `.claude/rules/docs.md` (loads when you touch `docs/`); a Claude hook checks every edited file.
- Docs, code, identifiers, commit messages, issues, and CLAUDE.md files are English; app copy is Indonesian (quoted verbatim when an issue refers to it).

## Code comments

- English, and only for what the code can't say (why, invariants, workarounds). Full rule: `.claude/rules/code-comments.md` (loads when you touch app code).
- Files hashed by the chat eval guards (`frozen` in `hygiene.toml`, from the `sourceHashes`/`sha256` maps in `apps/mobile/test/fixtures/*_protocol*.json`) stay byte-identical, comments included, unless you re-freeze them per `docs/llm-evals.md` (Re-freeze the eval guards).
