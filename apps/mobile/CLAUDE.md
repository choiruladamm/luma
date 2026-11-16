# Luma mobile (Flutter)

Paths in this file are relative to `apps/mobile` unless they start with `docs/` (repo root). Run commands via the root `Makefile`; anything else with `fvm flutter` / `fvm dart` from `apps/mobile`.

## Codegen and schema

- After changing a Drift table or a freezed model: `make gen`. Commit the generated `*.g.dart` / `*.freezed.dart` files.
- Real user data already lives on the iPhone, so every table change bumps `schemaVersion`, adds an `onUpgrade` step, and adds a test in `test/data/migration_test.dart`. User data is kept through migrations, never by deleting the app. Follow the `drift-migration` skill for the steps.

## Builds on device

Two separate apps (separate data and Keychain):

| App | Bundle id | iOS | Android | From |
|---|---|---|---|---|
| **Luma** (real user data) | `id.ruma.luma` | `make release` | `make release-android`, `make apk` | `master` only |
| **Luma Dev** (black icon) | `id.ruma.luma.dev` | `make dev`, debug `make run f=dev` | `make dev-android`, debug `make run-android f=dev` | feature branches |

Feature branches always build Luma Dev: unstable schema migrations would touch real data, and Drift can't downgrade. Android always uses `--flavor` (`prod` / `dev`); release is signed with a fixed keystore via `android/key.properties` (gitignored, see README), no 7-day expiry. Details: `docs/architecture.md` (Gotcha platform).

## Architecture

Layered (UI → data), hybrid structure:

```
lib/
├── data/database/      # Drift AppDatabase + appDatabaseProvider
├── data/services/      # file storage, OpenRouter, secure storage, backend client
├── data/repositories/  # source of truth, raw data → domain models
├── domain/             # pure logic (grouping, parsers); models/ = immutable models (freezed)
├── routing/router.dart # routerProvider + Routes
└── ui/
    ├── core/           # Stabilo theme, shared widgets
    └── features/<feature>/{views,view_models}/   # screen = <Name>View in <name>_view.dart
```

- State: Riverpod 3, providers written by hand (no `riverpod_generator`), declared next to the class they expose. `Notifier` = ViewModel. `.autoDispose` for per-screen state; services/DB without autoDispose.
- Main provider names are fixed in `docs/architecture.md` (`booksStreamProvider`, `groupAiProvider`, etc.): use those names.
- Routing: go_router. Shell tabs Rak · Cari buku · Atur (`/`, `/discover`, `/settings`, `LumaNavBar` in `AppShell`); outside the shell `/reader/:bookId`, `/reader/:bookId/breakdown/:chapterId/:groupIndex` (Bedahin, only pushed from the Artinya sheet), chat. Navigate with `Routes` constants. Artinya sheet, Aa, table of contents = `showModalBottomSheet`.
- Colors from `context.stabilo`, text from `StabiloType`, sizes/radii/motion/shadows from `stabilo_tokens.dart` (`Space`, `Radii`, `Layout`, `Motion`, `Elevation`). Widgets only use tokens; add a new value as a token there first.
- Shared components in `ui/core/widgets/`, reuse them (component-specific sizes may live there): `AppButton.primary/secondary/danger`, `CircleButton`, `AppIcon` + `AppIcons` (Hugeicons Stroke Rounded), `Tag.section/status`, `showAppSheet` + `SheetFrame`, `showToast`, `showConfirmDialog`, `showAppMenu`, `AppField`, `BookCover` (real cover / default from title), `BookCard`, `StatusButton` / `StatusCard` / `IconTile` / `Skeleton` (AI answer states, Artinya sheet + Bedahin). Single-feature components stay in their feature folder.

## Flutter skills

Load only the skill the current work needs:

- `flutter-apply-architecture-best-practices`: new feature touching data/repository/ViewModel, or structural refactor.
- `flutter-setup-declarative-routing`: route/navigation changes.
- `flutter-build-responsive-layout`: layout broken at certain screen sizes.
- `flutter-add-widget-test`: writing screen/component widget tests.

Skill conflicts with this file → follow this file (the architecture skill shows `ChangeNotifier` + `provider`/`get_it`; here it's Riverpod).

## Tests

The suite is large and slow (1200+ tests, ~2 min). Do not run it all by default.

- Small fixes and features that don't touch other features: `dart format` + `dart analyze` on touched files, plus only the covering tests: `fvm flutter test <files or dirs> --timeout 30s` (e.g. `test/ui/features/<feature>`, `test/ui/core/<widget>_test.dart`, `test/data/<repo>_test.dart`).
- Full `make check` (l10n, format, analyze, all tests) only for wide changes: Drift schema/migrations, models/codegen, shared widgets used across features, routing/theme, or many features at once. Never re-run the full suite to re-confirm a small follow-up fix.
- Run the full suite in the background and watch the log; log silent > 20 s = hung, not slow.

Folder layout follows Mibu (`choiruladamm/mibu`, `apps/mobile/test/`), but **widget tests never touch Drift** (in Mibu that made tests hang). Every finished issue ships its tests:

- `test/domain/`: pure logic (grouping, parsers, cover, LLM JSON parsing, reading percentage).
- `test/data/`: repositories, schema, and **Drift streams** with plain `test()` (real event loop), in-memory DB `AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true))`. Backup/restore round-trips go here.
- `test/ui/core/`: shared widgets.
- `test/ui/features/<feature>/<screen>_test.dart`: widget test per screen. Override the **view-model provider** (e.g. `booksStreamProvider.overrideWith((ref) => controller.stream)`) with fake data, not the DB. External services (OpenRouter, file picker, secure storage, backend) are faked too.

Widget test traps:

- `testWidgets` runs on a fake clock: Drift streams, file IO, and image decoding need the real event loop. Drift stream → override its provider. Files/images → wrap `pumpWidget` + wait in `tester.runAsync`, then `pump()`.
- `make test` uses `--timeout 30s`: a hung test fails instead of stalling. Hung = find what waits on the real event loop; keep the timeout at 30 s.
- `--timeout` only cuts the **test**, not tearDown or a process that won't exit. Two known causes:
  - A `StreamController` the app listens to: write `tearDown(() => unawaited(controller.close()))`. An awaited `close()` waits forever if the test fails midway.
  - A provider reading the DB that wasn't overridden: `appDatabaseProvider` deliberately throws under `flutter test` (checks `FLUTTER_TEST`) to fail fast. Opening a new screen in a test → override that screen's providers too.
- Test font is Ahem (1em per glyph): set `tester.view.physicalSize = Size(900, 1400)`, `devicePixelRatio = 1`, `addTearDown(tester.view.reset)` to avoid false overflows. Need real text metrics (cover layout)? Load the font with `FontLoader` in `setUpAll`.
- `test/flutter_test_config.dart` sets `driftRuntimeOptions.dontWarnAboutMultipleDatabases = true` (each test opens its own DB).

Integration tests are out of MVP scope.

## Data rules that are easy to miss

- The DB stores **file names** only; absolute paths are resolved at runtime (the iOS container changes on every reinstall).
- Other tables point at `chapters.id`, not chapter order.
- `paragraphIndex` and `groupIndex` must be stable. Changing parsing/grouping logic → bump `parserVersion`, re-import, delete that book's `ai_results`.
- Data that is backed up lives in Drift (`settings` table). API keys only in `flutter_secure_storage`, never backed up.
- EPUB parsing and backup zipping run in an isolate.
- The Cari kata index (`paragraph_fts`, FTS5 external-content) is tied to `paragraphs` rowids and kept in sync by triggers. Never write to `paragraphs` with triggers disabled; after `VACUUM` / swapping the DB file, call `rebuildBookSearchIndex()` (restore already does). Details: `docs/book-search.md`.
- The LLM model is read from Settings, reasoning is disabled, JSON output is validated (`docs/llm.md`).
- Backend calls: follow the client rules in `docs/backend.md` (Aturan client): no timers that call the backend, minimum spacing per automatic trigger, dedupe via `sync_outbox`, bounded retries on network/5xx only.

## Copy

UI supports Indonesian / English via `lib/l10n/app_id.arb` (template) and `app_en.arb`; access from UI with `context.l10n`. Indonesian copy stays casual Gen Z ("Rak buku lo", "Bentar, lagi mikir...") and follows the design boards; English is casual and natural. Add whole sentences with placeholders/plurals, then `make l10n`; commit the generated source. Numbers/dates use formatters with an explicit locale. AI language, book text, user input, and stored chat history stay in their original language. Details: `docs/i18n.md`.
