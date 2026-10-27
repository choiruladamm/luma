import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/domain/models/book.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  });
  tearDown(() => db.close());

  Future<int> insertBook({String hash = 'abc'}) => db
      .into(db.books)
      .insert(
        BooksCompanion.insert(
          sourceType: SourceType.epub,
          title: 'Pride and Prejudice',
          author: const Value('Jane Austen'),
          fileName: Value('$hash.epub'),
          hash: Value(hash),
          parserVersion: 1,
          totalChars: 120,
        ),
      );

  Future<int> insertChapter(int bookId, int sortOrder) => db
      .into(db.chapters)
      .insert(
        ChaptersCompanion.insert(
          bookId: bookId,
          sortOrder: sortOrder,
          title: 'Chapter $sortOrder',
          charOffset: sortOrder * 60,
        ),
      );

  Future<int> insertSession(int bookId) => db
      .into(db.chatSessions)
      .insert(
        ChatSessionsCompanion.insert(
          bookId: bookId,
          contentRevision: 1,
          title: 'Tema buku',
        ),
      );

  Future<int> insertTurn(int sessionId, {int sequence = 0}) => db
      .into(db.chatTurns)
      .insert(
        ChatTurnsCompanion.insert(
          sessionId: sessionId,
          sequence: sequence,
          question: 'Kenapa?',
          phase: 'preparing',
          model: 'test/model',
          promptVersion: 1,
        ),
      );

  test('chat snapshots survive chapter replacement; session and book delete cascade', () async {
    final keep = await insertBook(hash: 'keep');
    final gone = await insertBook(hash: 'gone');
    final chapter = await insertChapter(gone, 0);
    final keptSession = await insertSession(keep);
    final deletedSession = await insertSession(gone);
    final archivedSession = await insertSession(gone);
    await insertTurn(keptSession);
    await insertTurn(deletedSession);
    final turn = await insertTurn(archivedSession);
    final snapshot =
        '[{"id":"S1","chapterId":$chapter,"paragraphIndex":0,"snapshot":"Bukti 🌿"}]';
    await (db.update(db.chatTurns)..where((t) => t.id.equals(turn))).write(
      ChatTurnsCompanion(
        sources: Value(snapshot),
        quote: Value(snapshot),
        answer: const Value('{"status":"partial","claims":[]}'),
        draft: const Value('Potongan mentah'),
        attempt: const Value(2),
        phase: const Value('cut'),
        error: const Value('network'),
        httpStatus: const Value(502),
      ),
    );
    await (db.delete(db.chapters)..where((c) => c.id.equals(chapter))).go();
    final archived = await (db.select(
      db.chatTurns,
    )..where((t) => t.id.equals(turn))).getSingle();
    expect(archived.sources, snapshot);
    expect(archived.quote, snapshot);
    expect(archived.answer, '{"status":"partial","claims":[]}');
    expect(
      (
        archived.draft,
        archived.attempt,
        archived.phase,
        archived.error,
        archived.httpStatus,
      ),
      ('Potongan mentah', 2, 'cut', 'network', 502),
    );
    await (db.delete(
      db.chatSessions,
    )..where((s) => s.id.equals(deletedSession))).go();
    expect((await db.select(db.chatTurns).get()).map((t) => t.sessionId), [
      keptSession,
      archivedSession,
    ]);
    await (db.delete(db.books)..where((b) => b.id.equals(gone))).go();
    expect((await db.select(db.chatSessions).get()).map((s) => s.id), [
      keptSession,
    ]);
    expect((await db.select(db.chatTurns).get()).map((t) => t.sessionId), [
      keptSession,
    ]);
  });

  test('chat order unique per session; payload defaults and opened time are independent', () async {
    final book = await insertBook();
    final first = await insertSession(book);
    final second = await insertSession(book);
    await insertTurn(first);
    await insertTurn(second);
    await expectLater(insertTurn(first), throwsA(isA<SqliteException>()));
    await expectLater(insertTurn(9999), throwsA(isA<SqliteException>()));
    final row = (await db.select(db.chatTurns).get()).first;
    expect(
      (
        row.attempt,
        row.draft,
        row.sources,
        row.quote,
        row.answer,
        row.error,
        row.httpStatus,
      ),
      (1, '', '[]', null, null, null, null),
    );
    final before = await (db.select(
      db.chatSessions,
    )..where((s) => s.id.equals(first))).getSingle();
    expect(before.manualTitle, isFalse);
    expect(before.lastOpenedAt, isNull);
    const scroll = '{"turnId":1,"blockIndex":0,"alignment":0.4}';
    final opened = DateTime(2026, 10, 28, 2);
    await (db.update(db.chatSessions)..where((s) => s.id.equals(first))).write(
      ChatSessionsCompanion(
        lastOpenedAt: Value(opened),
        scrollAnchor: const Value(scroll),
      ),
    );
    await (db.update(db.chatSessions)..where((s) => s.id.equals(first))).write(
      ChatSessionsCompanion(
        title: const Value('Judul manual'),
        manualTitle: const Value(true),
        updatedAt: Value(opened.add(const Duration(minutes: 1))),
      ),
    );
    final after = await (db.select(
      db.chatSessions,
    )..where((s) => s.id.equals(first))).getSingle();
    expect(after.lastOpenedAt, opened);
    expect(after.createdAt, before.createdAt);
    expect(after.scrollAnchor, scroll);
    expect(after.manualTitle, isTrue);
    expect((await db.select(db.books).getSingle()).contentRevision, 1);
    final indexes = await db
        .customSelect('PRAGMA index_info(chat_sessions_book_opened)')
        .get();
    expect(indexes.map((r) => r.read<String>('name')), [
      'book_id',
      'last_opened_at',
      'id',
    ]);
    // Unique constraint's automatic index also serves ordered turn queries.
    final plan = await db
        .customSelect(
          'EXPLAIN QUERY PLAN SELECT * FROM chat_turns WHERE session_id = 1 ORDER BY sequence',
        )
        .get();
    expect(
      plan.map((r) => r.read<String>('detail')).join(' '),
      contains('USING INDEX'),
    );
  });

  test('book → chapters → paragraphs round-trip in display order', () async {
    final bookId = await insertBook();
    // Inserted out of order: display order comes from sortOrder, not id.
    final second = await insertChapter(bookId, 1);
    final first = await insertChapter(bookId, 0);
    await db.batch(
      (b) => b.insertAll(db.paragraphs, [
        ParagraphsCompanion.insert(
          chapterId: first,
          paragraphIndex: 0,
          type: ParagraphType.heading,
          content: 'Chapter I',
        ),
        ParagraphsCompanion.insert(
          chapterId: first,
          paragraphIndex: 1,
          groupIndex: const Value(0),
          type: ParagraphType.paragraph,
          content: 'It is a truth universally acknowledged…',
        ),
      ]),
    );

    final chapters =
        await (db.select(db.chapters)
              ..where((c) => c.bookId.equals(bookId))
              ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
            .get();
    expect(chapters.map((c) => c.id), [first, second]);

    final paras =
        await (db.select(db.paragraphs)
              ..where((p) => p.chapterId.equals(first))
              ..orderBy([(p) => OrderingTerm.asc(p.paragraphIndex)]))
            .get();
    expect(paras.map((p) => p.type), [
      ParagraphType.heading,
      ParagraphType.paragraph,
    ]);
    expect(paras.first.groupIndex, isNull);
    expect(paras.last.groupIndex, 0);

    final book = await db.select(db.books).getSingle();
    expect(book.fileName, 'abc.epub');
    expect(book.lastOpenedAt, isNull);
  });

  test('same hash cannot be imported twice', () async {
    await insertBook();
    await expectLater(insertBook(), throwsA(isA<SqliteException>()));
  });

  test('same paragraph index in a chapter is rejected', () async {
    final chapterId = await insertChapter(await insertBook(), 0);
    final p = ParagraphsCompanion.insert(
      chapterId: chapterId,
      paragraphIndex: 0,
      type: ParagraphType.paragraph,
      content: 'x',
    );
    await db.into(db.paragraphs).insert(p);
    await expectLater(
      db.into(db.paragraphs).insert(p),
      throwsA(isA<SqliteException>()),
    );
  });

  test('deleting a book cascades to everything that hangs off it', () async {
    final keep = await insertBook(hash: 'keep');
    final gone = await insertBook(hash: 'gone');
    for (final bookId in [keep, gone]) {
      final chapterId = await insertChapter(bookId, 0);
      await db
          .into(db.paragraphs)
          .insert(
            ParagraphsCompanion.insert(
              chapterId: chapterId,
              paragraphIndex: 0,
              groupIndex: const Value(0),
              type: ParagraphType.paragraph,
              content: 'x',
            ),
          );
      await db
          .into(db.readingProgress)
          .insert(
            ReadingProgressCompanion.insert(
              bookId: Value(bookId),
              chapterId: chapterId,
              paragraphIndex: 0,
            ),
          );
      await db
          .into(db.aiResults)
          .insert(
            AiResultsCompanion.insert(
              chapterId: chapterId,
              groupIndex: 0,
              translations: '["x"]',
              meaning: 'y',
              model: 'z-ai/glm-5.3-flash',
            ),
          );
    }

    await (db.delete(db.books)..where((b) => b.id.equals(gone))).go();

    final chapters = await db.select(db.chapters).get();
    expect(chapters.map((c) => c.bookId), [keep]);
    final kept = chapters.single.id;
    expect((await db.select(db.paragraphs).get()).map((p) => p.chapterId), [
      kept,
    ]);
    expect((await db.select(db.readingProgress).get()).map((p) => p.bookId), [
      keep,
    ]);
    expect((await db.select(db.aiResults).get()).map((r) => r.chapterId), [
      kept,
    ]);
  });

  test('one cached AI result per group', () async {
    final chapterId = await insertChapter(await insertBook(), 0);
    final r = AiResultsCompanion.insert(
      chapterId: chapterId,
      groupIndex: 3,
      translations: '["a","b"]',
      meaning: 'm',
      model: 'z-ai/glm-5.3-flash',
    );
    await db.into(db.aiResults).insert(r);
    await expectLater(
      db.into(db.aiResults).insert(r),
      throwsA(isA<SqliteException>()),
    );
  });

  test('settings are key-value and upsert by key', () async {
    Future<void> put(String v) => db
        .into(db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(key: 'modelId', value: v),
        );
    await put('z-ai/glm-5.3-flash');
    await put('qwen/qwen3.8-flash');
    final rows = await db.select(db.settings).get();
    expect(rows.map((r) => (r.key, r.value)), [
      ('modelId', 'qwen/qwen3.8-flash'),
    ]);
  });
}
