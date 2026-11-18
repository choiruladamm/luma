# Luma mobile (Flutter)

Paths are relative to `apps/mobile` unless they start with `docs/` (repo root). Commands via the root `Makefile`; anything else with `fvm flutter` / `fvm dart` from `apps/mobile`. Architecture, fixed provider names, and routes: `docs/architecture.md`.

## Two apps on one phone

| App | Bundle id | Build | From |
|---|---|---|---|
| **Luma** (real user data) | `id.ruma.luma` | `make release`, `make release-android`, `make apk` | `master` only |
| **Luma Dev** (black icon) | `id.ruma.luma.dev` | `make dev`, `make dev-android`, debug `make run f=dev` / `make run-android f=dev` | feature branches |

- Feature branches build Luma Dev only: an unstable migration would touch real data, and Drift can't downgrade.
- `make run`, `make run-android`, and `make profile` without `f=dev` build the real Luma app and aren't guarded to `master`. On a feature branch always pass `f=dev`.
- Android release is signed with a fixed keystore via `android/key.properties` (gitignored, see README). Details: `docs/architecture.md` (Gotcha platform).

## Schema and codegen

- Any Drift table change: follow the `drift-migration` skill (`schemaVersion` bump, `onUpgrade` step, migration test). Real data on the iPhone is kept through migrations, never by reinstalling.
- After changing a Drift table or a freezed model: `make gen`, commit the generated `*.g.dart` / `*.freezed.dart`.

## Code rules

- Riverpod 3 with hand-written providers (no `riverpod_generator`), declared next to the class they expose. `Notifier` = ViewModel. `.autoDispose` for per-screen state; services and DB without it.
- Flutter skills (`flutter-apply-architecture-best-practices` and friends) show `ChangeNotifier` + `provider`/`get_it`. This app is Riverpod; on conflict this file wins.
- Widgets take every value from tokens: colors `context.stabilo`, text `StabiloType`, sizes/radii/motion/shadows from `lib/ui/core/theme/stabilo_tokens.dart`. A new value becomes a token there first.
- Reuse `lib/ui/core/widgets/` (buttons, sheets, toasts, dialogs, menus, fields, covers, AI-answer states) before writing a component. Single-feature components stay in their feature folder.
- Navigate with `Routes` constants. Artinya sheet, Aa, and table of contents are `showModalBottomSheet`.

## Data rules that are easy to miss

- The DB stores **file names** only; absolute paths are resolved at runtime (the iOS container changes on every reinstall).
- Other tables point at `chapters.id`, not chapter order.
- `paragraphIndex` and `groupIndex` must be stable. Changing parsing/grouping logic → bump `parserVersion`, re-import, delete that book's `ai_results`.
- Backed-up data lives in Drift (`settings` table). API keys only in `flutter_secure_storage`, never backed up.
- EPUB parsing and backup zipping run in an isolate.
- The Cari kata index (`paragraph_fts`, FTS5 external-content) is tied to `paragraphs` rowids and kept in sync by triggers. Write to `paragraphs` only with triggers enabled; after `VACUUM` or swapping the DB file, call `rebuildBookSearchIndex()` (restore already does). Details: `docs/book-search.md`.
- LLM calls read the model from Settings, send reasoning off (retried at minimal effort only for models that require reasoning), and validate JSON output (`docs/llm.md`).
- Backend calls follow `docs/backend.md` (Aturan client): no timers that call the backend, minimum spacing per automatic trigger, dedupe via `sync_outbox`, bounded retries on network/5xx only.

## Tests

The suite is 1200+ tests (~2 min); run it only when the change is wide.

- Default: `dart format` + `dart analyze` on touched files, then only the covering tests: `fvm flutter test <files or dirs> --timeout 30s` (e.g. `test/ui/features/<feature>`, `test/data/<repo>_test.dart`).
- Full `make check` (l10n, format, analyze, all tests) only for Drift schema/migrations, models/codegen, shared widgets, routing/theme, or several features at once. It rewrites files (format, l10n), so check `git status` afterwards. Run it in the background and watch the log: silent > 20 s = hung, not slow.
- A small follow-up fix re-runs only its covering tests.
- Every finished issue ships its tests. Folder layout and widget-test traps: `.claude/rules/flutter-tests.md`.

## Copy

UI is Indonesian / English via `lib/l10n/app_id.arb` (template) and `app_en.arb`, read with `context.l10n`. Indonesian copy is casual Gen Z ("Rak buku lo", "Bentar, lagi mikir...") and follows the design boards; English is casual and natural. Add whole sentences with placeholders/plurals, then `make l10n` and commit the generated source. Numbers/dates use formatters with an explicit locale. AI language, book text, user input, and stored chat history stay in their original language. Details: `docs/i18n.md`.
