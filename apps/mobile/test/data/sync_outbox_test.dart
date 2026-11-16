import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/database/sync_schema.dart';

AppDatabase _open() => AppDatabase(
  DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
);

Future<Map<String, int>> _outbox(AppDatabase db) async => {
  for (final r in await db.select(db.syncOutbox).get())
    '${r.kind} ${r.key}': r.updatedAt,
};

Future<Map<String, Object?>?> _data(
  AppDatabase db,
  String kind,
  String key,
) async {
  final row = await db
      .customSelect(
        syncKindsByName[kind]!.select,
        variables: [
          Variable(jsonEncode([key])),
        ],
      )
      .getSingleOrNull();
  return row == null
      ? null
      : jsonDecode(row.read<String>('data')) as Map<String, Object?>;
}

/// Buku EPUB (hash `h1`), Markdown (`notes`), satu bab tiap buku.
Future<void> _seed(AppDatabase db) async {
  await db.customStatement(
    "INSERT INTO books (id, source_type, title, hash, parser_version, "
    "total_chars, created_at, first_opened_at) "
    "VALUES (1, 'epub', 'Meditations', 'h1', 9, 100, 1790000000, 1790000060)",
  );
  await db.customStatement(
    "INSERT INTO books (id, source_type, title, book_key, parser_version, "
    "total_chars) VALUES (2, 'markdown', 'Notes', 'notes', 1, 10)",
  );
  await db.customStatement(
    'INSERT INTO chapters (id, book_id, sort_order, title, char_offset) '
    "VALUES (10, 1, 4, 'IV', 0), (20, 2, 0, 'I', 0)",
  );
  await db.delete(db.syncOutbox).go();
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = _open();
    await _seed(db);
  });
  tearDown(() => db.close());

  test('books queue under their natural key: hash or md:{bookKey}', () async {
    await db.customStatement("UPDATE books SET title = 'M' WHERE id = 1");
    await db.customStatement("UPDATE books SET title = 'N' WHERE id = 2");

    expect(
      (await _outbox(db)).keys,
      unorderedEquals(['book h1', 'book md:notes']),
    );
    final data = (await _data(db, 'book', 'h1'))!;
    expect(data['title'], 'M');
    expect(data['useDefaultCover'], false);
    expect(data['createdAt'], '2026-09-21T14:13:20.000Z');
    expect(data['finishedAt'], isNull);
  });

  test('many updates to one row collapse into one outbox entry', () async {
    for (var i = 0; i < 5; i++) {
      await db.customStatement(
        'INSERT OR REPLACE INTO reading_progress '
        '(book_id, chapter_id, paragraph_index) VALUES (1, 10, $i)',
      );
    }
    expect((await _outbox(db)).keys, ['reading_progress h1']);
    final data = (await _data(db, 'reading_progress', 'h1'))!;
    expect(data, containsPair('paragraphIndex', 4));
    expect(data, containsPair('chapterSortOrder', 4));
    expect(data, containsPair('parserVersion', 9));
  });

  test('AI results key by book/chapter order/group, ids stay local', () async {
    await db.customStatement(
      'INSERT INTO ai_results (chapter_id, group_index, translations, '
      "meaning, model, prompt_version) VALUES (10, 12, '[\"a\"]', 'm', 'x', 3)",
    );
    await db.customStatement(
      'INSERT INTO ai_breakdowns (chapter_id, group_index, body, source_hash, '
      "model, prompt_version) VALUES (20, 0, 'b', 's', 'x', 1)",
    );
    expect(
      (await _outbox(db)).keys,
      unorderedEquals(['ai_result h1/4/12', 'ai_breakdown md:notes/0/0']),
    );
    final data = (await _data(db, 'ai_result', 'h1/4/12'))!;
    expect(data['translations'], '["a"]');
    expect(data['promptVersion'], 3);
    expect(data.containsKey('chapterId'), isFalse);
  });

  test('only allowlisted settings queue', () async {
    await db.customStatement(
      "INSERT INTO settings (key, value) VALUES ('ai.model', 'm'), "
      "('backup.lastAt', 'x'), ('catalog.count', '9')",
    );
    expect((await _outbox(db)).keys, ['setting ai.model']);
    expect(await _data(db, 'setting', 'ai.model'), {'value': 'm'});
  });

  test('chat turns queue only once they stop running', () async {
    await db.customStatement(
      'INSERT INTO chat_sessions (id, book_id, content_revision, title, '
      "created_at) VALUES (5, 1, 1, 'T', 1790000000)",
    );
    await db.customStatement(
      'INSERT INTO chat_turns (id, session_id, sequence, question, phase, '
      "model, prompt_version) VALUES (7, 5, 0, 'Q', 'writing', 'm', 1)",
    );
    expect((await _outbox(db)).keys, ['chat_session h1/1790000000000']);

    await db.customStatement(
      "UPDATE chat_turns SET phase = 'done' WHERE id = 7",
    );
    expect((await _outbox(db)).keys, contains('chat_turn h1/1790000000000/0'));
  });

  test('deleting a book queues one tombstone, not its children', () async {
    await db.customStatement(
      'INSERT INTO ai_results (chapter_id, group_index, translations, '
      "meaning, model) VALUES (10, 0, '[]', 'm', 'x')",
    );
    await db.customStatement(
      'INSERT INTO chat_sessions (book_id, content_revision, title) '
      "VALUES (1, 1, 'T')",
    );
    await db.delete(db.syncOutbox).go();

    await db.customStatement('DELETE FROM books WHERE id = 1');

    expect((await _outbox(db)).keys, ['book h1']);
    expect(await _data(db, 'book', 'h1'), isNull); // baris hilang = tombstone
  });

  test('deleting one chat session queues its tombstone', () async {
    await db.customStatement(
      'INSERT INTO chat_sessions (id, book_id, content_revision, title, '
      "created_at) VALUES (5, 1, 1, 'T', 1790000000)",
    );
    await db.delete(db.syncOutbox).go();
    await db.customStatement('DELETE FROM chat_sessions WHERE id = 5');
    expect((await _outbox(db)).keys, ['chat_session h1/1790000000000']);
  });

  test('Drift upserts on a queued key do not trip the outbox PK', () async {
    // Regresi: `INSERT OR REPLACE` di trigger ditimpa policy upsert luar.
    for (var i = 0; i < 2; i++) {
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(key: 'shelf.sort', value: 'v$i'),
          );
      await db
          .into(db.readingProgress)
          .insertOnConflictUpdate(
            ReadingProgressCompanion.insert(
              bookId: const Value(1),
              chapterId: 10,
              paragraphIndex: i,
            ),
          );
    }
    expect(
      (await _outbox(db)).keys,
      unorderedEquals(['setting shelf.sort', 'reading_progress h1']),
    );
  });

  test('outbox time is the device clock in ms', () async {
    final before = DateTime.now().millisecondsSinceEpoch;
    await db.customStatement("UPDATE books SET title = 'M' WHERE id = 1");
    final at = (await _outbox(db))['book h1']!;
    expect(at, inInclusiveRange(before - 1000, before + 5000));
  });
}
