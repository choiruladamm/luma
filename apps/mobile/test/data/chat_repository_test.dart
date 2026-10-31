import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/chat_repository.dart';
import 'package:luma/data/repositories/chat_snapshot.dart';
import 'package:luma/domain/chat_prompt.dart';
import 'package:luma/domain/models/ai_reply.dart';
import 'package:luma/domain/models/book.dart';
import 'package:luma/domain/models/book_chat.dart';

void main() {
  late AppDatabase db;
  late ChatRepository repo;
  late ChatBookRef book, other;
  late int chapter, otherChapter;
  late DateTime now;
  const original = 'A 🌿 garden belongs to the keeper.';

  Future<int> addBook(String title) => db
      .into(db.books)
      .insert(
        BooksCompanion.insert(
          sourceType: SourceType.epub,
          title: title,
          parserVersion: 1,
          totalChars: 100,
        ),
      );
  Future<int> addChapter(int bookId) async {
    final id = await db
        .into(db.chapters)
        .insert(
          ChaptersCompanion.insert(
            bookId: bookId,
            sortOrder: 9,
            title: 'IX',
            charOffset: 0,
          ),
        );
    await db
        .into(db.paragraphs)
        .insert(
          ParagraphsCompanion.insert(
            chapterId: id,
            paragraphIndex: 2,
            type: ParagraphType.paragraph,
            content: original,
          ),
        );
    return id;
  }

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    now = DateTime.utc(2026, 10, 28);
    repo = ChatRepository(db, now: () => now);
    book = (bookId: await addBook('Garden'), contentRevision: 1);
    other = (bookId: await addBook('Other'), contentRevision: 1);
    chapter = await addChapter(book.bookId);
    otherChapter = await addChapter(other.bookId);
  });
  tearDown(() async {
    repo.dispose();
    await db.close();
  });

  SourceAnchor anchor({
    ChatBookRef? ref,
    int? chapterId,
    int start = 0,
    int? end,
  }) => SourceAnchor(
    book: ref ?? book,
    chapterId: chapterId ?? chapter,
    paragraphIndex: 2,
    start: start,
    end: end ?? original.length,
    paragraphHash: chatTextHash(original),
    snapshot: original.substring(start, end ?? original.length),
  );
  ChatSource source({SourceAnchor? a, String id = 'S1'}) =>
      ChatSource(id: id, chapterTitle: 'IX', anchors: [a ?? anchor()]);
  ChatAnswer answer(
    ChatSource s, {
    ChatAnswerStatus status = ChatAnswerStatus.answered,
  }) => ChatAnswer(
    status: status,
    blocks: [
      ChatAnswerBlock(text: 'Taman itu milik penjaganya.', sources: [s]),
    ],
  );
  Future<ChatTurn> first({
    ChatBookRef? ref,
    String question = ' Siapa penjaganya? ',
    ChatQuote? quote,
  }) => repo.createFirstTurn(
    ref ?? book,
    question: question,
    model: 'test/model',
    promptVersion: chatPromptVersion,
    quote: quote,
  );
  Future<List<ChatTurn>> turns(ChatTurn t) =>
      repo.watchTurns(t.book.bookId, t.sessionId).first;
  Future<List<ChatSession>> sessions([ChatBookRef? ref]) =>
      repo.watchSessions((ref ?? book).bookId).first;
  Future<ChatTurnRow> raw(ChatTurn t) =>
      (db.select(db.chatTurns)..where((r) => r.id.equals(t.id))).getSingle();
  Future<void> stop(ChatTurn t) async {
    expect(await repo.finalize(t.attemptRef, phase: ChatPhase.stopped), isTrue);
  }

  ChatSourceRef sourceRef(ChatTurn t, {String id = 'S1'}) => (
    bookId: t.book.bookId,
    sessionId: t.sessionId,
    turnId: t.id,
    attempt: t.attempt,
    sourceId: id,
  );

  test('explicit continue commits a verified source only, stale requests preserve progress', () async {
    final t = await first();
    final s = source();
    await repo.prepareSources(t.attemptRef, [s]);
    await repo.finalize(t.attemptRef, phase: ChatPhase.done, answer: answer(s));
    expect((await repo.resolveSource(sourceRef(t)))!.available, true);
    expect(await db.select(db.readingProgress).get(), isEmpty);
    await repo.continueReading(request: sourceRef(t));
    final saved = await db.select(db.readingProgress).getSingle();
    expect(
      (
        saved.bookId,
        saved.chapterId,
        saved.paragraphIndex,
        saved.paragraphOffset,
      ),
      (book.bookId, chapter, 2, 0),
    );
    final books = await db.select(db.books).get();
    expect(books.every((b) => b.readingSeconds == 0), true);
    final forged = (
      bookId: other.bookId,
      sessionId: t.sessionId,
      turnId: t.id,
      attempt: t.attempt,
      sourceId: 'S1',
    );
    await expectLater(repo.continueReading(request: forged), throwsStateError);
    await (db.update(db.books)..where((b) => b.id.equals(book.bookId))).write(
      const BooksCompanion(contentRevision: Value(2)),
    );
    await expectLater(
      repo.continueReading(request: sourceRef(t)),
      throwsStateError,
    );
    final unchanged = await db.select(db.readingProgress).getSingle();
    expect(unchanged, saved);
  });

  test(
    'entry quote visit validates imported text and continue remains explicit',
    () async {
      final quote = ChatQuote(
        anchors: [anchor()],
        chapterTitle: 'IX',
        translation: 'Terjemahan',
      );
      expect((await repo.resolveQuote(quote))!.source.chapterTitle, 'IX');
      expect(await db.select(db.readingProgress).get(), isEmpty);
      await repo.continueReading(quote: quote);
      final saved = await db.select(db.readingProgress).getSingle();
      await (db.update(db.paragraphs)
            ..where((p) => p.chapterId.equals(chapter)))
          .write(const ParagraphsCompanion(content: Value('Berubah')));
      expect(await repo.resolveQuote(quote), isNull);
      await expectLater(repo.continueReading(quote: quote), throwsStateError);
      expect(await db.select(db.readingProgress).getSingle(), saved);
    },
  );

  test(
    'reopening a quote finds its own session without creating or mixing books',
    () async {
      final quote = ChatQuote(anchors: [anchor()], chapterTitle: 'IX');
      expect(await repo.sessionForQuote(quote), isNull);
      final t = await first(quote: quote);
      await stop(t);
      final unrelated = await first(question: 'Topik lain');
      await stop(unrelated);
      expect(
        (await repo.sessionForQuote(
          ChatQuote(anchors: [anchor()], translation: 'Versi UI baru'),
        ))!.id,
        t.sessionId,
      );
      expect((await turns(t)).single.quote!.chapterTitle, 'IX');
      expect(
        await repo.sessionForQuote(
          ChatQuote(
            anchors: [anchor(ref: other, chapterId: otherChapter)],
          ),
        ),
        isNull,
      );
      await (db.update(db.books)..where((b) => b.id.equals(book.bookId))).write(
        const BooksCompanion(contentRevision: Value(2)),
      );
      await expectLater(repo.sessionForQuote(quote), throwsStateError);
    },
  );

  test(
    'history previews a valid answer and safely falls back for broken data',
    () async {
      final t = await first();
      final s = source();
      await repo.prepareSources(t.attemptRef, [s]);
      await repo.finalize(
        t.attemptRef,
        phase: ChatPhase.done,
        answer: answer(s),
      );
      expect((await sessions()).single.preview, 'Taman itu milik penjaganya.');
      await (db.update(db.chatTurns)..where((r) => r.id.equals(t.id))).write(
        const ChatTurnsCompanion(answer: Value('{broken')),
      );
      expect((await sessions()).single.preview, t.question);
    },
  );

  test('source resolver is read only and rejects forged ownership and stale sources', () async {
    final t = await first();
    final s = source();
    await repo.prepareSources(t.attemptRef, [s]);
    await repo.finalize(t.attemptRef, phase: ChatPhase.done, answer: answer(s));
    final before = await db.customSelect('SELECT * FROM books').get();
    final beforeTurn = await raw(t);
    expect((await repo.resolveSource(sourceRef(t)))!.available, isTrue);
    expect(await repo.resolveSource(sourceRef(t, id: 'fake')), isNull);
    expect(
      await repo.resolveSource((
        bookId: other.bookId,
        sessionId: t.sessionId,
        turnId: t.id,
        attempt: t.attempt,
        sourceId: 'S1',
      )),
      isNull,
    );
    expect(
      await repo.resolveSource((
        bookId: book.bookId,
        sessionId: 99999,
        turnId: t.id,
        attempt: t.attempt,
        sourceId: 'S1',
      )),
      isNull,
    );
    expect(
      await repo.resolveSource((
        bookId: book.bookId,
        sessionId: t.sessionId,
        turnId: 99999,
        attempt: t.attempt,
        sourceId: 'S1',
      )),
      isNull,
    );
    expect(
      await repo.resolveSource((
        bookId: book.bookId,
        sessionId: t.sessionId,
        turnId: t.id,
        attempt: 2,
        sourceId: 'S1',
      )),
      isNull,
    );
    expect((await raw(t)).toJson(), beforeTurn.toJson());
    expect(
      (await db.customSelect('SELECT * FROM books').get()).map((r) => r.data),
      before.map((r) => r.data),
    );
    expect(await db.select(db.readingProgress).get(), isEmpty);
    expect(await db.select(db.readingSessions).get(), isEmpty);
    await (db.update(db.paragraphs)..where((p) => p.chapterId.equals(chapter)))
        .write(const ParagraphsCompanion(content: Value('Changed')));
    final stale = await repo.resolveSource(sourceRef(t));
    expect(stale!.available, isFalse);
    expect(stale.source.text, original);
    await (db.update(db.books)..where((b) => b.id.equals(book.bookId))).write(
      const BooksCompanion(contentRevision: Value(2)),
    );
    expect((await repo.resolveSource(sourceRef(t)))!.available, isFalse);
  });

  test('chapterNumbers ranks chapters by sortOrder, per book', () async {
    final first = await db
        .into(db.chapters)
        .insert(
          ChaptersCompanion.insert(
            bookId: book.bookId,
            sortOrder: 3,
            title: 'III',
            charOffset: 0,
          ),
        );
    final numbers = await repo.chapterNumbers(book.bookId);
    expect(numbers, {first: 1, chapter: 2});
    expect(await repo.chapterNumbers(other.bookId), {otherChapter: 1});
  });

  test('source resolver rejects foreign chapters, changed ranges, hashes and missing paragraphs', () async {
    final t = await first();
    await repo.prepareSources(t.attemptRef, [source()]);
    await repo.finalize(
      t.attemptRef,
      phase: ChatPhase.done,
      answer: answer(source()),
    );
    for (final mutation in <Map<String, Object>>[
      {'chapterId': otherChapter},
      {'paragraphIndex': 999},
      {'paragraphHash': chatTextHash('wrong')},
      {'start': 1},
      {'end': original.length + 1},
    ]) {
      final data = ChatSnapshot.sourcesData([source()]);
      final anchors = data.single['anchors'] as List;
      (anchors.single as Map).addAll(mutation);
      await (db.update(db.chatTurns)..where((r) => r.id.equals(t.id))).write(
        ChatTurnsCompanion(sources: Value(jsonEncode(data))),
      );
      expect(
        (await repo.resolveSource(sourceRef(t)))?.available ?? false,
        isFalse,
      );
    }
  });

  test('source resolver allows complete provisional blocks, revokes failed and deleted turns', () async {
    final t = await first();
    await repo.prepareSources(t.attemptRef, [source()]);
    expect((await repo.resolveSource(sourceRef(t)))!.available, isFalse);
    const draft =
        '{"parts":[{"text":"Keeper","kind":"book","source_ids":["S1"]}';
    await repo.checkpoint(t.attemptRef, draft: draft, phase: ChatPhase.writing);
    expect((await repo.resolveSource(sourceRef(t)))!.available, isTrue);
    final seen = <bool?>[];
    final sub = repo
        .watchSource(sourceRef(t))
        .listen((s) => seen.add(s?.available));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await repo.finalize(
      t.attemptRef,
      phase: ChatPhase.failed,
      error: AiError.invalidResponse,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect((await repo.resolveSource(sourceRef(t)))!.available, isFalse);
    await repo.deleteSession(book.bookId, t.sessionId);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(await repo.resolveSource(sourceRef(t)), isNull);
    expect(seen, containsAllInOrder([true, false, null]));
    await sub.cancel();
  });

  test('first send is atomic, normalized, deterministic, and no empty draft session', () async {
    expect(await sessions(), isEmpty);
    await expectLater(first(question: '  '), throwsFormatException);
    await expectLater(
      repo.createFirstTurn(
        book,
        question: 'Valid?',
        model: '',
        promptVersion: 1,
      ),
      throwsFormatException,
    );
    await expectLater(
      first(ref: (bookId: 999, contentRevision: 1)),
      throwsStateError,
    );
    expect(await db.select(db.chatSessions).get(), isEmpty);
    expect(await db.select(db.chatTurns).get(), isEmpty);
    final t = await first();
    expect(t.question, 'Siapa penjaganya?');
    expect((t.sequence, t.attempt, t.phase), (0, 1, ChatPhase.preparing));
    final s = (await sessions()).single;
    expect(s.title, t.question);
    expect(s.preview, t.question);
    expect(s.manualTitle, isFalse);
    expect(s.lastOpenedAt!.isAtSameMomentAs(now), isTrue);
    expect(s.invalid, isFalse);
  });

  test('quote validation rolls back first send; multi-window snapshot preserves emoji', () async {
    await expectLater(
      first(
        quote: ChatQuote(
          anchors: [anchor(ref: other, chapterId: otherChapter)],
        ),
      ),
      throwsFormatException,
    );
    await expectLater(
      first(
        quote: ChatQuote(
          anchors: [
            SourceAnchor(
              book: book,
              chapterId: chapter,
              paragraphIndex: 2,
              start: 3,
              end: 4,
              paragraphHash: chatTextHash(original),
              snapshot: original.substring(3, 4),
            ),
          ],
        ),
      ),
      throwsFormatException,
    );
    expect(await sessions(), isEmpty);
    final quote = ChatQuote(
      anchors: [anchor(end: 4), anchor(start: 5)],
      translation: 'Pendamping UI',
    );
    final t = await first(quote: quote);
    final saved = (await turns(t)).single.quote!;
    expect(
      saved.anchors.map((a) => a.snapshot),
      quote.anchors.map((a) => a.snapshot),
    );
    expect(saved.translation, 'Pendamping UI');
    await expectLater(
      repo.prepareSources(t.attemptRef, [source(a: anchor(end: 4))]),
      throwsFormatException,
    );
    expect(await repo.prepareSources(t.attemptRef, [source()]), isTrue);
  });

  test('concurrent append rejects duplicate pending; retries keep one question and generation', () async {
    final t = await first();
    await expectLater(
      repo.appendTurn(
        book,
        t.sessionId,
        question: 'Lagi?',
        model: 'm',
        promptVersion: 1,
      ),
      throwsStateError,
    );
    await stop(t);
    final results = await Future.wait([
      for (var i = 0; i < 2; i++)
        repo
            .appendTurn(
              book,
              t.sessionId,
              question: 'Lagi?',
              model: 'm',
              promptVersion: 1,
            )
            .then<Object>((t) => t, onError: (Object e) => e),
    ]);
    expect(results.whereType<ChatTurn>(), hasLength(1));
    expect(results.whereType<StateError>(), hasLength(1));
    final next = results.whereType<ChatTurn>().single;
    expect(next.sequence, 1);
    await stop(next);
    final retried = await repo.retry(
      next.attemptRef,
      model: 'new/model',
      promptVersion: 2,
    );
    expect(
      (
        retried.id,
        retried.sessionId,
        retried.sequence,
        retried.question,
        retried.attempt,
      ),
      (next.id, next.sessionId, 1, 'Lagi?', 2),
    );
    expect(retried.createdAt, next.createdAt);
    expect(
      (
        retried.model,
        retried.promptVersion,
        retried.draft,
        retried.answer,
        retried.error,
      ),
      ('new/model', 2, '', null, null),
    );
    expect(await turns(t), hasLength(2));
    expect(
      await repo.checkpoint(
        next.attemptRef,
        draft: 'late',
        phase: ChatPhase.writing,
      ),
      isFalse,
    );
    expect(
      await repo.finalize(
        next.attemptRef,
        phase: ChatPhase.failed,
        error: AiError.network,
      ),
      isFalse,
    );
    await expectLater(
      repo.retry(t.attemptRef, model: 'm', promptVersion: 1),
      throwsStateError,
    );
  });

  test(
    'sessions/books isolate streams, previews, operations, and automatic title',
    () async {
      final one = await first();
      final two = await first(question: 'Sesi kedua');
      final foreign = await first(ref: other, question: 'Buku lain');
      expect((await sessions()).map((s) => s.preview), [
        'Sesi kedua',
        'Siapa penjaganya?',
      ]);
      expect(await repo.watchTurns(other.bookId, one.sessionId).first, isEmpty);
      await expectLater(
        repo.appendTurn(
          other,
          one.sessionId,
          question: 'x',
          model: 'm',
          promptVersion: 1,
        ),
        throwsStateError,
      );
      await expectLater(
        repo.rename(other, one.sessionId, 'x'),
        throwsStateError,
      );
      await expectLater(
        repo.markOpened(other.bookId, one.sessionId),
        throwsStateError,
      );
      await expectLater(
        repo.deleteSession(other.bookId, one.sessionId),
        throwsStateError,
      );
      final forged = (
        book: other,
        sessionId: one.sessionId,
        turnId: one.id,
        attempt: one.attempt,
      );
      expect(await repo.finalize(forged, phase: ChatPhase.stopped), isFalse);
      await repo.rename(book, one.sessionId, '  Tema   🌿  ');
      await (db.update(db.books)..where((b) => b.id.equals(book.bookId))).write(
        const BooksCompanion(title: Value('New metadata')),
      );
      final renamed = (await sessions()).firstWhere(
        (s) => s.id == one.sessionId,
      );
      expect((renamed.title, renamed.manualTitle), ('Tema 🌿', true));
      await stop(one);
      await repo.appendTurn(
        book,
        one.sessionId,
        question: 'Follow up',
        model: 'm',
        promptVersion: 1,
      );
      expect(
        (await sessions()).firstWhere((s) => s.id == one.sessionId).title,
        'Tema 🌿',
      );
      expect((await turns(two)).single.question, 'Sesi kedua');
      expect((await turns(foreign)).single.question, 'Buku lain');
    },
  );

  test('activity order differs from last opened; read/list/rename never mark opened', () async {
    final one = await first();
    now = now.add(const Duration(seconds: 2));
    final two = await first(question: 'Second');
    expect((await repo.lastOpenedSession(book.bookId))!.id, two.sessionId);
    now = now.add(const Duration(seconds: 2));
    await repo.rename(book, one.sessionId, 'Older session renamed');
    expect((await sessions()).first.id, one.sessionId);
    expect((await repo.lastOpenedSession(book.bookId))!.id, two.sessionId);
    final updated = (await sessions()).first.updatedAt;
    now = now.add(const Duration(seconds: 2));
    await repo.markOpened(book.bookId, one.sessionId);
    expect((await sessions()).first.updatedAt, updated);
    expect((await repo.lastOpenedSession(book.bookId))!.id, one.sessionId);
    final fallback = await repo.deleteSession(book.bookId, one.sessionId);
    expect(fallback!.id, two.sessionId);
    expect(await repo.deleteSession(book.bookId, two.sessionId), isNull);
    expect(await sessions(), isEmpty);
  });

  test('checkpoint throttles token writes, flushes terminal buffered tail, never shrinks', () async {
    final t = await first();
    expect(
      await repo.checkpoint(t.attemptRef, draft: 'x', phase: ChatPhase.writing),
      isFalse,
    );
    await repo.prepareSources(t.attemptRef, []);
    expect(
      await repo.checkpoint(t.attemptRef, draft: 'a', phase: ChatPhase.writing),
      isTrue,
    );
    for (var i = 2; i <= 100; i++) {
      now = now.add(const Duration(milliseconds: 1));
      expect(
        await repo.checkpoint(
          t.attemptRef,
          draft: 'a' * i,
          phase: ChatPhase.writing,
        ),
        isTrue,
      );
    }
    expect((await raw(t)).draft, 'a'); // 100 callbacks, only first persisted.
    expect(
      await repo.checkpoint(t.attemptRef, draft: 'a', phase: ChatPhase.writing),
      isFalse,
    );
    expect(
      await repo.checkpoint(
        t.attemptRef,
        draft: 'a' * 100,
        phase: ChatPhase.waiting,
      ),
      isFalse,
    );
    now = now.add(const Duration(milliseconds: 500));
    await repo.checkpoint(
      t.attemptRef,
      draft: 'a' * 101,
      phase: ChatPhase.writing,
    );
    expect((await raw(t)).draft, 'a' * 101);
    await repo.checkpoint(
      t.attemptRef,
      draft: 'a' * 1125,
      phase: ChatPhase.writing,
    );
    expect(
      (await raw(t)).draft,
      'a' * 1125,
    ); // byte threshold flush before 500ms.
    await repo.checkpoint(
      t.attemptRef,
      draft: '${'a' * 1125}🌿',
      phase: ChatPhase.writing,
    );
    expect(await repo.finalize(t.attemptRef, phase: ChatPhase.stopped), isTrue);
    final saved = (await turns(t)).single;
    expect(
      (saved.phase, saved.draft, saved.trustedHistory),
      (ChatPhase.stopped, '${'a' * 1125}🌿', false),
    );
    expect(
      await repo.checkpoint(
        t.attemptRef,
        draft: 'late',
        phase: ChatPhase.writing,
      ),
      isFalse,
    );
  });

  test('sources freeze before stream; final answer owns exact snapshot and fixed note', () async {
    final t = await first();
    final s = source();
    await expectLater(
      repo.prepareSources(t.attemptRef, [
        source(
          a: anchor(ref: other, chapterId: otherChapter),
        ),
      ]),
      throwsFormatException,
    );
    await expectLater(
      repo.prepareSources(t.attemptRef, [s, s]),
      throwsFormatException,
    );
    expect(await repo.prepareSources(t.attemptRef, [s]), isTrue);
    expect(await repo.prepareSources(t.attemptRef, []), isFalse);
    await expectLater(
      repo.finalize(
        t.attemptRef,
        phase: ChatPhase.done,
        answer: answer(source(a: anchor(start: 5))),
      ),
      throwsFormatException,
    );
    expect((await raw(t)).phase, 'waiting');
    expect(
      await repo.finalize(
        t.attemptRef,
        phase: ChatPhase.done,
        answer: answer(s, status: ChatAnswerStatus.partial),
      ),
      isTrue,
    );
    final saved = (await turns(t)).single;
    expect(
      saved.answer!.note,
      'Sebagian pertanyaan belum punya bukti yang cukup di sumber ini.',
    );
    expect(
      saved.answer!.blocks.single.sources.single.anchors.single.snapshot,
      original,
    );
    expect(saved.trustedHistory, isTrue);
    expect((await raw(t)).sources, contains('paragraphHash'));
  });

  test('legacy session accepts natural replies and hydrates both formats without rewriting old answers', () async {
    final old = await first();
    final s = source();
    await repo.prepareSources(old.attemptRef, [s]);
    await repo.finalize(
      old.attemptRef,
      phase: ChatPhase.done,
      answer: answer(s),
    );
    final oldRaw = (await raw(old)).answer;
    final next = await repo.appendTurn(
      book,
      old.sessionId,
      question: 'Coba terapkan ke situasi gua.',
      model: 'test/model',
      promptVersion: chatPromptVersion,
    );
    await repo.prepareSources(next.attemptRef, [s]);
    final reply = ChatAnswer(
      status: ChatAnswerStatus.partial,
      formatVersion: 2,
      blocks: [
        ChatAnswerBlock(
          text: 'Gagasan dalam buku.',
          sources: [s],
          layout: ChatAnswerLayout.quote,
        ),
        ChatAnswerBlock(
          text: 'Saran penerapan gua.',
          sources: [s],
          kind: ChatAnswerKind.interpretation,
          layout: ChatAnswerLayout.bullet,
        ),
        ChatAnswerBlock(
          text: 'Tambahan di luar buku.',
          sources: [],
          kind: ChatAnswerKind.external,
        ),
        ChatAnswerBlock(
          text: 'Bukti untuk bagian terakhir belum ketemu.',
          sources: [],
          kind: ChatAnswerKind.conversation,
        ),
      ],
    );
    expect(
      await repo.finalize(
        next.attemptRef,
        phase: ChatPhase.done,
        answer: reply,
      ),
      isTrue,
    );
    final restored = await turns(next);
    expect(restored.first.answer!.formatVersion, 1);
    expect((await raw(old)).answer, oldRaw);
    expect(restored.last.answer!.formatVersion, 2);
    expect(
      restored.last.answer!.blocks.map((b) => b.kind),
      ChatAnswerKind.values,
    );
    expect(restored.last.answer!.blocks.map((b) => b.layout), [
      ChatAnswerLayout.quote,
      ChatAnswerLayout.bullet,
      ChatAnswerLayout.paragraph,
      ChatAnswerLayout.paragraph,
    ]);
    expect(restored.last.answer!.note, isEmpty);
    expect(restored.last.trustedHistory, isTrue);
  });

  test('restart interrupts once, preserves partial and sources, explicit retry clears generation', () async {
    final t = await first(quote: ChatQuote(anchors: [anchor()]));
    await repo.prepareSources(t.attemptRef, [source()]);
    await repo.checkpoint(
      t.attemptRef,
      draft: 'Partial 🌿',
      phase: ChatPhase.writing,
    );
    repo.dispose();
    repo = ChatRepository(db, now: () => now);
    expect(await repo.recoverInterrupted(), 1);
    final interrupted = (await turns(t)).single;
    expect(
      (interrupted.phase, interrupted.draft, interrupted.trustedHistory),
      (ChatPhase.interrupted, 'Partial 🌿', false),
    );
    expect(interrupted.quote!.text, original);
    expect((await raw(t)).sources, contains('S1'));
    await repo.recoverInterrupted();
    final next = await repo.retry(
      interrupted.attemptRef,
      model: 'm',
      promptVersion: 1,
    );
    await repo
        .recoverInterrupted(); // cached bootstrap never interrupts new request.
    expect((await raw(t)).phase, 'preparing');
    expect((await raw(t)).sources, '[]');
    expect(next.attempt, 2);
    expect(
      await repo.finalize(t.attemptRef, phase: ChatPhase.stopped),
      isFalse,
    );
  });

  test('no-key failure terminates immediately and only explicit retry starts another attempt', () async {
    final t = await first();
    expect(
      await repo.finalize(
        t.attemptRef,
        phase: ChatPhase.failed,
        error: AiError.noApiKey,
      ),
      isTrue,
    );
    final failed = (await turns(t)).single;
    expect(
      (failed.phase, failed.error, failed.trustedHistory),
      (ChatPhase.failed, AiError.noApiKey, false),
    );
    expect((await turns(t)).single.attempt, 1);
    final next = await repo.retry(
      failed.attemptRef,
      model: 'm',
      promptVersion: 1,
    );
    expect(next.attempt, 2);
  });

  test('delete pending session rejects late writes and preserves other paid/reader data', () async {
    final t = await first();
    final otherSession = await first(question: 'Keep');
    await db
        .into(db.readingProgress)
        .insert(
          ReadingProgressCompanion.insert(
            bookId: Value(book.bookId),
            chapterId: chapter,
            paragraphIndex: 2,
            paragraphOffset: const Value(0.3),
          ),
        );
    await db
        .into(db.aiResults)
        .insert(
          AiResultsCompanion.insert(
            chapterId: chapter,
            groupIndex: 0,
            translations: '["Terjemahan"]',
            meaning: 'Makna',
            model: 'm',
          ),
        );
    await repo.deleteSession(book.bookId, t.sessionId);
    expect(await repo.prepareSources(t.attemptRef, []), isFalse);
    expect(
      await repo.checkpoint(
        t.attemptRef,
        draft: 'late',
        phase: ChatPhase.writing,
      ),
      isFalse,
    );
    expect(
      await repo.finalize(t.attemptRef, phase: ChatPhase.stopped),
      isFalse,
    );
    expect(await repo.watchTurns(book.bookId, t.sessionId).first, isEmpty);
    expect((await turns(otherSession)).single.question, 'Keep');
    expect(
      (await db.select(db.readingProgress).getSingle()).paragraphOffset,
      0.3,
    );
    expect((await db.select(db.aiResults).getSingle()).meaning, 'Makna');
    expect(await db.select(db.books).get(), hasLength(2));
  });

  test('revision changes leave readable archive; stale mutations and terminal writes are rejected', () async {
    final t = await first();
    await repo.prepareSources(t.attemptRef, [source()]);
    await repo.finalize(
      t.attemptRef,
      phase: ChatPhase.done,
      answer: answer(source()),
    );
    final pending = await first(question: 'Pending archive');
    await (db.update(db.books)..where((b) => b.id.equals(book.bookId))).write(
      const BooksCompanion(contentRevision: Value(2)),
    );
    await (db.delete(db.chapters)..where((c) => c.id.equals(chapter))).go();
    expect(
      (await turns(t)).single.answer!.blocks.single.sources.single.text,
      original,
    );
    final current = (bookId: book.bookId, contentRevision: 2);
    expect((await sessions()).every((s) => s.isArchived(current)), isTrue);
    expect(
      await repo.finalize(pending.attemptRef, phase: ChatPhase.stopped),
      isFalse,
    );
    await expectLater(
      repo.appendTurn(
        current,
        t.sessionId,
        question: 'x',
        model: 'm',
        promptVersion: 1,
      ),
      throwsStateError,
    );
    await expectLater(repo.rename(book, t.sessionId, 'x'), throwsStateError);
    await repo.markOpened(book.bookId, t.sessionId);
    await repo.deleteSession(book.bookId, t.sessionId);
    expect(await first(ref: current), isA<ChatTurn>());
  });

  test(
    'scroll anchors belong to session and do not update activity time',
    () async {
      final t = await first();
      final foreign = await first();
      final before = (await sessions())
          .firstWhere((s) => s.id == t.sessionId)
          .updatedAt;
      now = now.add(const Duration(seconds: 5));
      await expectLater(
        repo.saveScrollAnchor(book.bookId, t.sessionId, (
          turnId: foreign.id,
          blockIndex: 0,
          alignment: 0.5,
        )),
        throwsFormatException,
      );
      await expectLater(
        repo.saveScrollAnchor(book.bookId, t.sessionId, (
          turnId: t.id,
          blockIndex: 0,
          alignment: double.nan,
        )),
        throwsA(
          anyOf(isA<JsonUnsupportedObjectError>(), isA<FormatException>()),
        ),
      );
      const alignment = 0.4;
      final pos = (turnId: t.id, blockIndex: 0, alignment: alignment);
      await repo.saveScrollAnchor(book.bookId, t.sessionId, pos);
      final saved = (await sessions()).firstWhere((s) => s.id == t.sessionId);
      expect(saved.scrollAnchor, pos);
      expect(saved.updatedAt, before);
      await repo.saveScrollAnchor(book.bookId, t.sessionId, null);
      expect(
        (await sessions()).firstWhere((s) => s.id == t.sessionId).scrollAnchor,
        isNull,
      );
    },
  );

  test('live output validates current paragraph even if mutation omitted revision bump', () async {
    final t = await first();
    await repo.prepareSources(t.attemptRef, [source()]);
    await (db.update(db.paragraphs)..where((p) => p.chapterId.equals(chapter)))
        .write(const ParagraphsCompanion(content: Value('Changed')));
    await expectLater(
      repo.finalize(
        t.attemptRef,
        phase: ChatPhase.done,
        answer: answer(source()),
      ),
      throwsFormatException,
    );
    expect((await raw(t)).answer, isNull);
  });

  test('disposed repository cannot write into restored/reused IDs', () async {
    final t = await first();
    final old = repo;
    old.dispose();
    repo = ChatRepository(db, now: () => now);
    await repo.recoverInterrupted();
    final retried = await repo.retry(
      t.attemptRef,
      model: 'm',
      promptVersion: 1,
    );
    expect(
      await old.checkpoint(
        retried.attemptRef,
        draft: 'late',
        phase: ChatPhase.writing,
      ),
      isFalse,
    );
    expect(
      await old.finalize(retried.attemptRef, phase: ChatPhase.stopped),
      isFalse,
    );
    expect((await raw(t)).phase, 'preparing');
  });

  test(
    'provider disposal invalidates old callback; no service/network dependency',
    () async {
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      final provided = container.read(chatRepositoryProvider);
      expect(container.read(chatRepositoryProvider), same(provided));
      final t = await provided.createFirstTurn(
        book,
        question: 'x',
        model: 'm',
        promptVersion: 1,
      );
      container.dispose();
      expect(
        await provided.finalize(t.attemptRef, phase: ChatPhase.stopped),
        isFalse,
      );
    },
  );

  test(
    'streams emit committed updates and do not leak other sessions',
    () async {
      final one = await first();
      final two = await first();
      final events = <List<ChatTurn>>[];
      final initial = Completer<void>();
      final changed = Completer<void>();
      final sub = repo.watchTurns(book.bookId, one.sessionId).listen((value) {
        events.add(value);
        if (!initial.isCompleted) initial.complete();
        if (value.single.phase == ChatPhase.stopped && !changed.isCompleted) {
          changed.complete();
        }
      });
      addTearDown(sub.cancel);
      await initial.future;
      await stop(two);
      await stop(one);
      await changed.future;
      expect(
        events.every((batch) => batch.length == 1 && batch.single.id == one.id),
        isTrue,
      );
      expect(events.last.single.phase, ChatPhase.stopped);
    },
  );

  test('Unicode title limits and question byte limits are enforced at repository boundary', () async {
    final t = await first(question: '${'🌿' * 121}?');
    final s = (await sessions()).single;
    expect(s.title.runes.length, 120);
    expect(s.title.endsWith('…'), isTrue);
    await repo.rename(book, t.sessionId, '🌿' * 120);
    await expectLater(
      repo.rename(book, t.sessionId, '🌿' * 121),
      throwsFormatException,
    );
    await expectLater(
      first(question: 'a' * (chatQuestionBytes + 1)),
      throwsFormatException,
    );
    await expectLater(
      first(question: String.fromCharCode(0xd800)),
      throwsFormatException,
    );
    expect(await sessions(), hasLength(1));
  });

  test('completed and no-source answers hydrate canonically; invalid terminal combinations never persist', () async {
    final t = await first();
    await expectLater(
      repo.finalize(t.attemptRef, phase: ChatPhase.done),
      throwsFormatException,
    );
    await expectLater(
      repo.finalize(t.attemptRef, phase: ChatPhase.failed),
      throwsFormatException,
    );
    await repo.prepareSources(t.attemptRef, [source()]);
    expect(
      await repo.finalize(
        t.attemptRef,
        phase: ChatPhase.done,
        answer: answer(source()),
      ),
      isTrue,
    );
    expect((await turns(t)).single.trustedHistory, isTrue);
    final n = await repo.appendTurn(
      book,
      t.sessionId,
      question: 'Tidak ada?',
      model: 'm',
      promptVersion: 1,
    );
    final noSource = ChatAnswer(status: ChatAnswerStatus.notFound, blocks: []);
    await repo.finalize(n.attemptRef, phase: ChatPhase.done, answer: noSource);
    final saved = (await turns(t)).last;
    expect(saved.answer!.note, noSource.note);
    expect(saved.answer!.blocks, isEmpty);
    expect(saved.trustedHistory, isTrue);
    await expectLater(
      repo.retry(saved.attemptRef, model: 'm', promptVersion: 1),
      throwsStateError,
    );
    await expectLater(
      repo.retry(t.attemptRef, model: 'm', promptVersion: 1),
      throwsStateError,
    );
  });

  test('first-send stream publishes full transaction; newest activity and preview come from same session', () async {
    final emitted = Completer<List<ChatSession>>();
    final sub = repo.watchSessions(book.bookId).listen((rows) {
      if (rows.isNotEmpty && !emitted.isCompleted) emitted.complete(rows);
    });
    addTearDown(sub.cancel);
    final t = await first();
    final rows = await emitted.future;
    expect(rows.single.id, t.sessionId);
    expect(rows.single.preview, t.question);
    final before = await repo.lastOpenedSession(book.bookId);
    await stop(t);
    now = now.add(const Duration(seconds: 2));
    await repo.appendTurn(
      book,
      t.sessionId,
      question: 'Follow up only here',
      model: 'm',
      promptVersion: 1,
    );
    final separate = await first(question: 'Separate');
    final list = await sessions();
    expect(list.first.id, separate.sessionId);
    expect(list.last.preview, 'Follow up only here');
    expect(list.last.lastOpenedAt, before!.lastOpenedAt);
  });

  test('bootstrap recovers unknown phase and cut retry preserves quote but resets sources/error', () async {
    final t = await first(quote: ChatQuote(anchors: [anchor()]));
    await repo.prepareSources(t.attemptRef, [source()]);
    await repo.checkpoint(
      t.attemptRef,
      draft: 'Incomplete',
      phase: ChatPhase.writing,
    );
    await repo.finalize(
      t.attemptRef,
      phase: ChatPhase.cut,
      error: AiError.network,
    );
    final next = await repo.retry(t.attemptRef, model: 'm', promptVersion: 1);
    expect(next.quote!.text, original);
    expect(
      (next.draft, next.answer, next.error, next.attempt),
      ('', null, null, 2),
    );
    await (db.update(db.chatTurns)..where((r) => r.id.equals(t.id))).write(
      const ChatTurnsCompanion(phase: Value('future-unknown')),
    );
    repo.dispose();
    repo = ChatRepository(db, now: () => now);
    expect(await repo.recoverInterrupted(), 1);
    expect((await turns(t)).single.phase, ChatPhase.interrupted);
    expect((await turns(t)).single.trustedHistory, isFalse);
    await db.delete(db.books).go();
    expect(
      await repo.finalize(next.attemptRef, phase: ChatPhase.stopped),
      isFalse,
    );
  });

  test('corrupt snapshot matrix cannot crash hydration or become trusted history', () async {
    final t = await first();
    await repo.prepareSources(t.attemptRef, [source()]);
    await repo.finalize(
      t.attemptRef,
      phase: ChatPhase.done,
      answer: answer(source()),
    );
    final valid = await raw(t);
    for (final mutation in <ChatTurnsCompanion>[
      const ChatTurnsCompanion(sources: Value('{broken')),
      const ChatTurnsCompanion(quote: Value('{"anchors":[]}')),
      const ChatTurnsCompanion(
        answer: Value(
          '{"status":"answered","claims":[{"text":"x","sourceIds":["S999"]}]}',
        ),
      ),
      const ChatTurnsCompanion(answer: Value('{"status":"wrong","claims":[]}')),
      const ChatTurnsCompanion(
        answer: Value('{"status":"answered","claims":[]}'),
      ),
      const ChatTurnsCompanion(error: Value('alien')),
      const ChatTurnsCompanion(attempt: Value(0)),
      const ChatTurnsCompanion(sequence: Value(-1)),
      const ChatTurnsCompanion(httpStatus: Value(900)),
      const ChatTurnsCompanion(question: Value('')),
      ChatTurnsCompanion(
        sources: Value(
          jsonEncode(
            ChatSnapshot.sourcesData([
              source(
                a: anchor(ref: other, chapterId: otherChapter),
              ),
            ]),
          ),
        ),
      ),
    ]) {
      await (db.update(
        db.chatTurns,
      )..where((r) => r.id.equals(t.id))).write(valid.toCompanion(true));
      await (db.update(
        db.chatTurns,
      )..where((r) => r.id.equals(t.id))).write(mutation);
      final decoded = (await turns(t)).single;
      expect(
        decoded.error,
        AiError.invalidResponse,
        reason: mutation.toString(),
      );
      expect(decoded.trustedHistory, isFalse);
      expect(decoded.answer, isNull);
    }
    await (db.update(
      db.chatTurns,
    )..where((r) => r.id.equals(t.id))).write(valid.toCompanion(true));
    await (db.update(db.chatTurns)..where((r) => r.id.equals(t.id))).write(
      const ChatTurnsCompanion(phase: Value('unknown'), answer: Value(null)),
    );
    expect((await turns(t)).single.phase, ChatPhase.interrupted);
    await (db.update(db.chatSessions)..where((s) => s.id.equals(t.sessionId)))
        .write(const ChatSessionsCompanion(scrollAnchor: Value('{bad')));
    expect((await sessions()).single.invalid, isTrue);
    await repo.deleteSession(book.bookId, t.sessionId);
    expect(await sessions(), isEmpty);
  });
  test('lifecycle lookup is book-scoped and book identity stream follows revision/deletion', () async {
    final t = await first();
    expect((await repo.session(book.bookId, t.sessionId))!.id, t.sessionId);
    expect(await repo.session(other.bookId, t.sessionId), isNull);
    final stream = StreamIterator(repo.watchBook(book.bookId));
    try {
      expect(await stream.moveNext(), true);
      expect(stream.current, book);
      await (db.update(db.books)..where((b) => b.id.equals(book.bookId))).write(
        const BooksCompanion(contentRevision: Value(2)),
      );
      expect(await stream.moveNext(), true);
      expect(stream.current, (bookId: book.bookId, contentRevision: 2));
      await (db.delete(db.books)..where((b) => b.id.equals(book.bookId))).go();
      expect(await stream.moveNext(), true);
      expect(stream.current, isNull);
    } finally {
      await stream.cancel();
    }
  });
}
