---
paths: ["apps/mobile/test/**"]
---

# Flutter tests

Paths relative to `apps/mobile`. **Widget tests never touch Drift** (it makes them hang).

## Where tests go

- `test/domain/`: pure logic (grouping, parsers, cover, LLM JSON parsing, reading percentage).
- `test/data/`: repositories, schema, and Drift streams with plain `test()` (real event loop), in-memory DB `AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true))`. Backup/restore round-trips go here.
- `test/ui/core/`: shared widgets.
- `test/ui/features/<feature>/<screen>_test.dart`: one widget test per screen. Override the **view-model provider** with fake data (e.g. `booksStreamProvider.overrideWith((ref) => controller.stream)`), not the DB. Fake external services too (OpenRouter, file picker, secure storage, backend).

## Widget test traps

- `testWidgets` runs on a fake clock; Drift streams, file IO, and image decoding need the real event loop. Drift stream → override its provider. Files/images → wrap `pumpWidget` + wait in `tester.runAsync`, then `pump()`.
- Keep `--timeout 30s` so a hung test fails. Hung = find what waits on the real event loop.
- `--timeout` cuts only the test, not tearDown or a process that won't exit. Two known causes:
  - A `StreamController` the app listens to: `tearDown(() => unawaited(controller.close()))`. An awaited `close()` waits forever if the test failed midway.
  - A provider reading the DB that wasn't overridden: `appDatabaseProvider` throws under `flutter test` to fail fast. A test that opens a new screen overrides that screen's providers too.
- Test font is Ahem (1em per glyph): set `tester.view.physicalSize = Size(900, 1400)`, `devicePixelRatio = 1`, `addTearDown(tester.view.reset)` to avoid false overflows. Real text metrics (cover layout) → load the font with `FontLoader` in `setUpAll`.
- `test/flutter_test_config.dart` sets `driftRuntimeOptions.dontWarnAboutMultipleDatabases = true` (each test opens its own DB).
