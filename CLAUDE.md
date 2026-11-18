# Luma

iOS + Android book reader (EPUB, Markdown, PDF; personal dogfooding app): tap a paragraph → Indonesian translation + meaning from an LLM, without leaving the reading page. Local-first: the on-device Drift DB is the source of truth; the backend only adds accounts, subsidized AI keys, cloud backup, and sync.

Apps: `apps/mobile` (Flutter), `apps/backend` (Cloudflare Worker API), `apps/dashboard` (admin Worker on the backend's D1). Each has its own CLAUDE.md.

## Sources of truth

- **Product, data model, flows:** `docs/` (index `docs/README.md`). Read the doc for a feature before working on it. `docs/ideas/` only when asked. Cite docs by file path (`docs/llm.md`), not section number.
- **UI design:** Stabilo in Claude Design, https://claude.ai/artifact/EBwv9zJBLZQJa5WWYiaJ7F. Read the board named in the issue with the Artifact tool. Every screen has a light and a dark version.
- **Tasks and progress:** GitHub issues labeled `area:*`; one issue = one unit of work. Status lives in issues and the parent issue's checklist.

## Commands

Root `Makefile` (`make help`): mobile targets bare (`make test`), backend `backend-*`, dashboard `dashboard-*`.

- Run only the checks for what you changed (see each app's CLAUDE.md). Commit only after they exit 0, as its own command, never chained behind `grep` or `;`.
- The hand-off states which checks ran and whether the full suite was skipped.
- After touching `docs/` or doc citations in comments: `make docs-check`.

## Issues

- Start an issue only when every dependency on its **Tergantung** line is closed. Tick its scope checklist when done.
- Milestone `MVP` is done except dogfooding (#29). Outside MVP, status labels:
  - `status:ready`: clear plan; start once dependencies are closed.
  - `status:deferred`: waiting on its **Dibuka kalau** trigger. Trigger happened → `status:ready`.
  - `status:idea`: undecided; may be closed `wontfix`.
- New issue, idea, or deferred item: create it with a status label, add it to its parent issue, add a `(#N)` link in the relevant doc.
- Closed/merged doesn't prove it works on a device. Record device checks in the issue.

## Cross-app rules

- **Environments:** Luma Dev (`id.ruma.luma.dev`) ↔ backend env `dev` (`luma-api-dev.chrl.cloud`); Luma (`id.ruma.luma`) ↔ env `prod` (`luma-api.chrl.cloud`). Feature branches touch dev only; prod builds, deploys, and migrations come from `master`.
- **User data survives every fix:** through Drift migrations on device and D1 migrations on the backend.
- **API contract:** request/response examples in `apps/backend/test/fixtures/contract/`, tested by both vitest and Dart. An endpoint change updates the fixture, the backend, and the Dart client together.
- **Cloudflare free tier:** backend code and client code that calls it fit the free tier: no polling, debounce/batch, bounded retries, streamed files. Every change to how the app calls the backend updates the budget table in `docs/backend.md` (Aturan free tier).
- **Secrets:** plaintext API keys and tokens live only in `flutter_secure_storage` (device) and `wrangler secret` (backend). Never in the Drift DB, backups, `wrangler.jsonc`, or git. (The backend keeps users' AI keys AES-GCM encrypted in D1.)

## Docs and language

- `docs/` describes how the system works now. A behavior change that a doc describes (names, routes, tables, limits, flows, quoted copy) updates that doc in the same commit.
- Docs hold no progress, dates, or branch names; at most one line pointing to the parent issue. Old values stay only where the reason still matters, marked old ("angka lama; sekarang …").
- Docs, issues, and app copy are Indonesian; code, identifiers, commit messages, and CLAUDE.md files are English.

## Code comments

- Comments explain why. Issue numbers only for open work (`TODO(#N): ...`) or evidence the code can't show (`spike #34: 30/30 valid`); which issue added the code goes in the commit message.
- Cite a doc (`docs/<file>.md, <Section>`) only for a rule not visible from the file. The comment must make sense without opening the doc, and the path and section must exist.
- Files hashed by the chat eval guards (`sha256` / `sourceHashes` in `apps/mobile/test/fixtures/*_protocol*.json`) stay byte-identical, comments included, unless you re-freeze them per `docs/llm-evals.md` (Pembekuan ulang guard).
