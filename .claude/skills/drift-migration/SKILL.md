---
name: drift-migration
description: Change a Drift table in apps/mobile (add/alter/drop a column, table, index, trigger or FTS table) with a schemaVersion bump, onUpgrade step and migration test. Use whenever a change touches apps/mobile/lib/data/database/ table definitions.
---

# Drift schema migration

Real user data lives on the iPhone and in old backups, which are migrated on restore. A table change without a migration corrupts or loses that data, and Drift can't downgrade. `drift_dev make-migrations` doesn't work here (the `paragraphs.text` column breaks its snapshot code), so migrations are hand-written.

Files: `apps/mobile/lib/data/database/app_database.dart` (tables, `schemaVersion`, `onCreate`, `onUpgrade`), `apps/mobile/test/data/migration_test.dart` (fixtures + tests).

## Steps

1. **Fixture for the current version first.** In `migration_test.dart`, make sure a `vN` fixture exists for the current `schemaVersion` N (the exact SQL a fresh install at N creates). Fixtures build on the previous one (`[...v16, ...]` or a `replaceFirst` on one `CREATE TABLE`). Add it if missing, before touching the tables.
2. **Change the table** in `app_database.dart`. New columns are nullable or have a default, so existing rows stay valid.
3. **Bump `schemaVersion`** to N+1.
4. **Add the `onUpgrade` step**: `if (from < N+1) { ... }` at the end, using `m.addColumn` / `m.createTable` / `m.createIndex` or `customStatement` for FTS/triggers. Mirror anything `onCreate` creates by hand (FTS tables, triggers): a fresh install and a migrated DB must end up identical.
5. **Sync**: if the table or column is synced, update `lib/data/database/sync_schema.dart` (`syncKinds`, triggers) and backfill `sync_outbox` in the upgrade step, like v17 → v18 does.
6. **Codegen**: `make gen`, commit the generated `*.g.dart`.
7. **Test** in `migration_test.dart`:
   - `vN → vN+1` test: open with `_old(vN, N)` (seeds a book, chapter, progress, AI result), assert the user data survived and new columns/tables have the expected values, then `expect(await _shape(db), await _shape(_open()))`.
   - The `v$version → now` loop must still pass for older fixtures.
8. **Backend branch**: on `feat/backend`, the new version number comes after the latest `schemaVersion` on `master`. If `master` moves ahead, renumber the step and its test when merging `master` in.
9. **Checks**: schema changes are wide, so run `make check`. Install on Luma Dev only (`make dev`), never the real Luma app, until merged to `master`.

## Don'ts

- Never edit an existing `if (from < X)` step or an old fixture; add a new step.
- Never write to `paragraphs` with FTS triggers disabled; after swapping the DB file call `rebuildBookSearchIndex()` (`docs/book-search.md`).
- Changing parsing/grouping is not a schema migration: bump `parserVersion` instead (see `apps/mobile/CLAUDE.md`, data rules).
