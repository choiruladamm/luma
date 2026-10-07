import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';

/// Schema lama persis kayak yang kebuat di iPhone (dan di backup lama).
const v1 = [
  '''CREATE TABLE "books" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "source_type" TEXT NOT NULL, "book_key" TEXT NULL UNIQUE, "title" TEXT NOT NULL, "author" TEXT NULL, "file_name" TEXT NULL, "cover_name" TEXT NULL, "hash" TEXT NULL UNIQUE, "parser_version" INTEGER NOT NULL, "total_chars" INTEGER NOT NULL, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), "last_opened_at" INTEGER NULL)''',
  '''CREATE TABLE "chapters" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "book_id" INTEGER NOT NULL REFERENCES books (id) ON DELETE CASCADE, "sort_order" INTEGER NOT NULL, "chapter_number" INTEGER NULL, "title" TEXT NOT NULL, "char_offset" INTEGER NOT NULL)''',
  '''CREATE TABLE "paragraphs" ("chapter_id" INTEGER NOT NULL REFERENCES chapters (id) ON DELETE CASCADE, "paragraph_index" INTEGER NOT NULL, "group_index" INTEGER NULL, "type" TEXT NOT NULL, "text" TEXT NOT NULL, PRIMARY KEY ("chapter_id", "paragraph_index"))''',
  '''CREATE TABLE "reading_progress" ("book_id" INTEGER NOT NULL REFERENCES books (id) ON DELETE CASCADE, "chapter_id" INTEGER NOT NULL REFERENCES chapters (id) ON DELETE CASCADE, "paragraph_index" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), PRIMARY KEY ("book_id"))''',
  '''CREATE TABLE "ai_results" ("chapter_id" INTEGER NOT NULL REFERENCES chapters (id) ON DELETE CASCADE, "group_index" INTEGER NOT NULL, "translations" TEXT NOT NULL, "meaning" TEXT NOT NULL, "model" TEXT NOT NULL, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), PRIMARY KEY ("chapter_id", "group_index"))''',
  '''CREATE TABLE "settings" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, PRIMARY KEY ("key"))''',
  'CREATE INDEX chapters_book_order ON chapters (book_id, sort_order)',
  'CREATE INDEX paragraphs_chapter_group ON paragraphs (chapter_id, group_index)',
];

/// v2: books dapet firstOpenedAt & readingSeconds (install baru v2).
final v2 = [
  '''CREATE TABLE "books" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "source_type" TEXT NOT NULL, "book_key" TEXT NULL UNIQUE, "title" TEXT NOT NULL, "author" TEXT NULL, "file_name" TEXT NULL, "cover_name" TEXT NULL, "hash" TEXT NULL UNIQUE, "parser_version" INTEGER NOT NULL, "total_chars" INTEGER NOT NULL, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), "last_opened_at" INTEGER NULL, "first_opened_at" INTEGER NULL, "reading_seconds" INTEGER NOT NULL DEFAULT 0)''',
  ...v1.skip(1),
];

/// v3: reading_progress dapet paragraph_offset.
final v3 = [
  for (final sql in v2)
    sql.startsWith('CREATE TABLE "reading_progress"')
        ? sql.replaceFirst(
            '"paragraph_index" INTEGER NOT NULL,',
            '"paragraph_index" INTEGER NOT NULL, "paragraph_offset" REAL NOT NULL DEFAULT 0.0,',
          )
        : sql,
];

AppDatabase _open([void Function(dynamic raw)? setup]) => AppDatabase(
  DatabaseConnection(
    NativeDatabase.memory(setup: setup),
    closeStreamsSynchronously: true,
  ),
);

/// Kolom tiap tabel + index, buat bandingin hasil migrasi sama DB baru.
Future<Map<String, List<String>>> _shape(AppDatabase db) async {
  final shape = <String, List<String>>{};
  final entities = await db
      .customSelect(
        "SELECT type, name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' "
        'ORDER BY name',
      )
      .get();
  for (final e in entities) {
    final name = e.read<String>('name');
    shape[name] = e.read<String>('type') == 'table'
        ? [
            for (final c
                in await db.customSelect('PRAGMA table_info("$name")').get())
              [
                c.read<String>('name'),
                c.read<String>('type'),
                c.read<int>('notnull'),
                c.read<String?>('dflt_value'),
                c.read<int>('pk'),
              ].join(' '),
          ]
        : [
            for (final c
                in await db.customSelect('PRAGMA index_info("$name")').get())
              c.read<String>('name'),
          ];
  }
  for (final cols in shape.values) {
    cols.sort(); // ALTER nambah kolom di akhir; urutan gak ngaruh ke Drift
  }
  return shape;
}

/// DB versi lama berisi satu buku, satu chapter, posisi baca di paragraf 3.
AppDatabase _old(List<String> schema, int version) => _open((raw) {
  for (final sql in schema) {
    raw.execute(sql);
  }
  raw.execute(
    "INSERT INTO books (source_type, title, hash, parser_version, "
    "total_chars, created_at, last_opened_at) "
    "VALUES ('epub', 'Meditations', 'a', 1, 100, 1790000000, 1790500000)",
  );
  raw.execute(
    "INSERT INTO chapters (book_id, sort_order, title, char_offset) "
    "VALUES (1, 0, 'I', 0)",
  );
  raw.execute(
    'INSERT INTO reading_progress (book_id, chapter_id, paragraph_index) '
    'VALUES (1, 1, 3)',
  );
  raw.execute(
    'INSERT INTO ai_results (chapter_id, group_index, translations, meaning, '
    "model) VALUES (1, 0, '[\"a\"]', 'm', 'x')",
  );
  raw.execute('PRAGMA user_version = $version');
});

void main() {
  for (final (version, schema) in [(1, v1), (2, v2), (3, v3)]) {
    test(
      'v$version → now: same schema as a fresh install, data kept',
      () async {
        final migrated = _old(schema, version);
        final fresh = _open();
        addTearDown(migrated.close);
        addTearDown(fresh.close);

        final book = await migrated.select(migrated.books).getSingle();
        expect(book.title, 'Meditations');
        expect(book.lastOpenedAt, isNotNull);
        expect(book.firstOpenedAt, isNull);
        expect(book.readingSeconds, 0);
        final progress = await migrated
            .select(migrated.readingProgress)
            .getSingle();
        expect(progress.paragraphIndex, 3);
        expect(progress.paragraphOffset, 0.0);
        // Translations from before #40 count as the old prompt.
        final cached = await migrated.select(migrated.aiResults).getSingle();
        expect(cached.promptVersion, 1);
        expect(await _shape(migrated), await _shape(fresh));
      },
    );
  }
}
