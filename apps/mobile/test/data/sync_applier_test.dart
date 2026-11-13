import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/database/sync_schema.dart';
import 'package:luma/data/repositories/sync_applier.dart';
import 'package:luma/data/services/file_storage.dart';
import 'package:luma/data/services/sync_service.dart';

AppDatabase _open() => AppDatabase(
  DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
);

/// Buku EPUB `h1` (parser 9), bab sortOrder 4 → id [chapterId].
Future<void> _book(AppDatabase db, {int parser = 9, int chapterId = 10}) async {
  await db.customStatement(
    'INSERT INTO books (id, source_type, title, hash, parser_version, '
    "total_chars, file_name, cover_name) VALUES (1, 'epub', 'Meditations', "
    "'h1', $parser, 100, 'h1.epub', 'h1.jpg')",
  );
  await db.customStatement(
    'INSERT INTO chapters (id, book_id, sort_order, title, char_offset) '
    "VALUES ($chapterId, 1, 4, 'IV', 0)",
  );
}

/// Record push device [db] (spec yang sama dengan push), dijadiin record pull.
Future<List<PulledRecord>> _records(AppDatabase db, {int? schema}) async {
  final out = <PulledRecord>[];
  for (final o in await db.select(db.syncOutbox).get()) {
    final spec = syncKindsByName[o.kind]!;
    final row = await db
        .customSelect(
          spec.select,
          variables: [
            Variable(jsonEncode([o.key])),
          ],
        )
        .getSingleOrNull();
    out.add(
      PulledRecord(
        kind: o.kind,
        key: o.key,
        updatedAt: o.updatedAt,
        schemaVersion: schema ?? db.schemaVersion,
        data: row == null
            ? null
            : (jsonDecode(row.read<String>('data')) as Map)
                  .cast<String, Object?>(),
      ),
    );
  }
  return out;
}

Future<List<String>> _outbox(AppDatabase db) async => [
  for (final o in await db.select(db.syncOutbox).get()) '${o.kind} ${o.key}',
];

Future<List<String>> _inbox(AppDatabase db) async => [
  for (final o in await db.select(db.syncInbox).get()) '${o.kind} ${o.key}',
];

void main() {
  late AppDatabase a;
  late AppDatabase b;
  late Directory tmp;
  late SyncApplier apply;

  /// Data baca + AI + chat di device A.
  Future<void> readOnA() async {
    await a.customStatement(
      'INSERT INTO reading_progress (book_id, chapter_id, paragraph_index, '
      'paragraph_offset) VALUES (1, 10, 37, 0.25)',
    );
    await a.customStatement(
      'INSERT INTO reading_sessions (book_id, chapter_id, started_at, seconds, '
      'start_char, end_char) VALUES (1, 10, 1790000000, 60, 0, 500)',
    );
    await a.customStatement(
      'INSERT INTO ai_results (chapter_id, group_index, translations, meaning, '
      "model, prompt_version, created_at) VALUES (10, 12, '[\"t\"]', 'm', "
      "'x', 3, 1790000100)",
    );
    await a.customStatement(
      'INSERT INTO ai_breakdowns (chapter_id, group_index, body, source_hash, '
      "model, prompt_version, created_at) VALUES (10, 12, 'b', 's', 'x', 2, "
      '1790000200)',
    );
    await a.customStatement(
      "INSERT INTO settings (key, value) VALUES ('ai.model', 'm1')",
    );
    await a.customStatement(
      'INSERT INTO chat_sessions (id, book_id, content_revision, title, '
      "created_at, updated_at) VALUES (5, 1, 1, 'Soal Stoa', 1790000300, "
      '1790000400)',
    );
    await a.customStatement(
      'INSERT INTO chat_turns (session_id, sequence, question, answer, phase, '
      "model, prompt_version, created_at, updated_at) VALUES (5, 0, 'Q', 'A', "
      "'done', 'x', 7, 1790000300, 1790000400)",
    );
  }

  setUp(() async {
    a = _open();
    b = _open();
    tmp = await Directory.systemTemp.createTemp('luma-apply-');
    final files = FileStorage(tmp);
    await files.ensureDirs();
    apply = SyncApplier(b, files);
    await _book(a);
    await _book(b, chapterId: 77); // ID lokal beda, kunci alami sama
    await b.delete(b.syncOutbox).go();
  });

  tearDown(() async {
    await a.close();
    await b.close();
    await tmp.delete(recursive: true);
  });

  test('two devices with the same book end up with the same data', () async {
    await readOnA();

    final outcome = await apply.apply(await _records(a), cursor: 'u1:7');

    expect(outcome.held, 0);
    final progress = await b.select(b.readingProgress).getSingle();
    expect((progress.chapterId, progress.paragraphIndex), (77, 37));
    expect(progress.paragraphOffset, 0.25);
    final ai = await b.select(b.aiResults).getSingle();
    expect((ai.chapterId, ai.groupIndex, ai.promptVersion), (77, 12, 3));
    expect((await b.select(b.aiBreakdowns).getSingle()).body, 'b');
    expect((await b.select(b.readingSessions).getSingle()).seconds, 60);
    final session = await b.select(b.chatSessions).getSingle();
    expect(session.title, 'Soal Stoa');
    final turn = await b.select(b.chatTurns).getSingle();
    expect(
      (turn.sessionId, turn.answer, turn.phase),
      (session.id, 'A', 'done'),
    );
    final settings = {
      for (final s in await b.select(b.settings).get()) s.key: s.value,
    };
    expect(settings['ai.model'], 'm1');
    expect(settings[pullCursorKey], 'u1:7');
    // Yang baru diterapin gak di-push balik.
    expect(await _outbox(b), isEmpty);
  });

  test('applying the same page twice changes nothing', () async {
    await readOnA();
    final records = await _records(a);
    await apply.apply(records);
    await apply.apply(records);
    expect(await b.select(b.readingSessions).get(), hasLength(1));
    expect(await b.select(b.chatTurns).get(), hasLength(1));
  });

  test('records for a book not on this device wait in the inbox', () async {
    await readOnA();
    await b.customStatement('DELETE FROM books');
    await b.delete(b.syncOutbox).go();

    final outcome = await apply.apply(await _records(a));

    expect(outcome.applied, 1); // cuma setting
    expect(await _inbox(b), containsAll(['book h1', 'ai_result h1/4/12']));
    expect((await apply.missingBooks()).single.key, 'h1');

    // Bukunya keimpor → coba lagi → semua masuk.
    await _book(b, chapterId: 88);
    await apply.retryInbox();
    expect(await _inbox(b), isEmpty);
    expect((await b.select(b.aiResults).getSingle()).chapterId, 88);
    expect(await b.select(b.chatTurns).get(), hasLength(1));
  });

  test('a different parser version or a newer schema waits', () async {
    await readOnA();
    await b.customStatement('UPDATE books SET parser_version = 10');
    await b.delete(b.syncOutbox).go();

    await apply.apply(await _records(a));
    expect(await _inbox(b), contains('ai_result h1/4/12'));
    expect(await b.select(b.aiResults).get(), isEmpty);

    final newer = await _records(a, schema: b.schemaVersion + 1);
    await b.customStatement('UPDATE books SET parser_version = 9');
    await apply.apply(newer);
    expect(await b.select(b.aiResults).get(), isEmpty);
    expect(
      (await b.select(b.syncInbox).get()).map((i) => i.schemaVersion).toSet(),
      {b.schemaVersion + 1},
    );
  });

  test('an unpushed newer local change wins and stays queued', () async {
    await readOnA();
    // Record A dari jam 1000, perubahan lokal B (belum di-push) jam 2000.
    await a.customStatement('UPDATE sync_outbox SET updated_at = 1000');
    final records = await _records(a);
    await b.customStatement(
      'INSERT INTO reading_progress (book_id, chapter_id, paragraph_index) '
      'VALUES (1, 77, 99)',
    );
    await b.customStatement('UPDATE sync_outbox SET updated_at = 2000');

    await apply.apply(records);

    expect((await b.select(b.readingProgress).getSingle()).paragraphIndex, 99);
    expect(await _outbox(b), contains('reading_progress h1'));
  });

  test(
    'books merge: earliest opened, longest read time, then pushed back',
    () async {
      await a.customStatement(
        "UPDATE books SET title = 'Renungan', reading_seconds = 100, "
        'first_opened_at = 1790000500',
      );
      await b.customStatement(
        'UPDATE books SET reading_seconds = 900, first_opened_at = 1790000000',
      );
      await b.delete(b.syncOutbox).go();

      await apply.apply(await _records(a));

      final book = await b.select(b.books).getSingle();
      expect(book.title, 'Renungan');
      expect(book.readingSeconds, 900);
      expect(book.firstOpenedAt!.millisecondsSinceEpoch ~/ 1000, 1790000000);
      expect(await _outbox(b), ['book h1']); // hasil merge ke server
    },
  );

  test(
    'a book tombstone deletes the book, its files and its waiting records',
    () async {
      final files = FileStorage(tmp);
      await files.book('h1.epub').writeAsString('epub');
      await files.cover('h1.jpg').writeAsString('jpg');
      await b.customStatement(
        "INSERT INTO sync_inbox (kind, key, data, updated_at, schema_version) "
        "VALUES ('ai_result', 'h1/4/1', '{}', 1, 18)",
      );

      await apply.apply([
        PulledRecord(
          kind: 'book',
          key: 'h1',
          updatedAt: 1,
          schemaVersion: b.schemaVersion,
        ),
      ]);

      expect(await b.select(b.books).get(), isEmpty);
      expect(await files.book('h1.epub').exists(), isFalse);
      expect(await files.cover('h1.jpg').exists(), isFalse);
      expect(await _inbox(b), isEmpty);
      expect(await _outbox(b), isEmpty); // gak di-push balik
    },
  );

  test('a chat turn that arrives before its session waits for it', () async {
    await readOnA();
    final records = await _records(a);
    final turn = records.where((r) => r.kind == 'chat_turn').toList();
    final session = records.where((r) => r.kind == 'chat_session').toList();

    await apply.apply(turn);
    expect(await _inbox(b), ['chat_turn ${turn.single.key}']);

    await apply.apply(session);
    await apply.retryInbox();
    expect(await b.select(b.chatTurns).get(), hasLength(1));
    expect(await _inbox(b), isEmpty);
  });

  test('a running local chat turn is never overwritten', () async {
    await readOnA();
    final records = await _records(a);
    await b.customStatement(
      'INSERT INTO chat_sessions (id, book_id, content_revision, title, '
      "created_at, updated_at) VALUES (9, 1, 1, 'T', 1790000300, 1790000400)",
    );
    await b.customStatement(
      'INSERT INTO chat_turns (session_id, sequence, question, phase, model, '
      "prompt_version) VALUES (9, 0, 'Q', 'writing', 'x', 7)",
    );

    await apply.apply(records);

    expect((await b.select(b.chatTurns).getSingle()).phase, 'writing');
  });
}
