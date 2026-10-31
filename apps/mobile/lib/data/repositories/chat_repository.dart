import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/chat_steps.dart';
import '../../domain/chat_prompt.dart';
import '../../domain/chat_preview.dart';
import '../../domain/chat_exploration.dart';
import '../../domain/models/ai_reply.dart';
import '../../domain/models/book_chat.dart';
import '../database/app_database.dart';
import 'chat_snapshot.dart';

/// Penyimpanan saja: tidak membaca API key atau memulai network/hydration request.
class ChatRepository {
  ChatRepository(this._db, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _now;
  Future<int>? _recovery;
  bool _disposed = false;
  final _pending = <ChatAttemptRef, _Checkpoint>{};

  /// Panggil sebelum DB diganti/ditutup; callback repository lama menjadi no-op.
  void dispose() {
    _disposed = true;
    _pending.clear();
  }

  void _open() {
    if (_disposed) throw StateError('Repository chat sudah ditutup');
  }

  /// Sekali per lifetime repository, sebelum read/write pertama. Tanpa resend.
  Future<int> recoverInterrupted() {
    _open();
    return _recovery ??=
        (_db.update(_db.chatTurns)..where(
              (t) => t.phase.isNotIn(
                ChatPhase.values.where((p) => !p.isRunning).map((p) => p.name),
              ),
            ))
            .write(
              ChatTurnsCompanion(
                phase: const Value('interrupted'),
                updatedAt: Value(_now()),
              ),
            );
  }

  Future<void> _ready() async {
    _open();
    await recoverInterrupted();
    _open();
  }

  Future<bool> _callbackReady() async {
    if (_disposed) return false;
    await recoverInterrupted();
    return !_disposed;
  }

  Stream<List<ChatSession>> watchSessions(int bookId) async* {
    await _ready();
    yield* _db
        .customSelect(
          'SELECT s.*, t.question AS preview, t.answer AS preview_answer, '
          't.sources AS preview_sources, t.phase AS preview_phase, t.error AS preview_error '
          'FROM chat_sessions s LEFT JOIN chat_turns t ON t.id = '
          '(SELECT id FROM chat_turns WHERE session_id = s.id ORDER BY sequence DESC LIMIT 1) '
          'WHERE s.book_id = ? ORDER BY s.updated_at DESC, s.id DESC',
          variables: [Variable.withInt(bookId)],
          readsFrom: {_db.chatSessions, _db.chatTurns},
        )
        .watch()
        .map(
          (rows) =>
              List.unmodifiable([for (final row in rows) _sessionPreview(row)]),
        );
  }

  ChatSession _sessionPreview(QueryRow row) {
    final sessionRow = _db.chatSessions.map(row.data);
    final session = ChatSnapshot.session(sessionRow);
    var preview = row.read<String?>('preview');
    if (row.read<String?>('preview_phase') == ChatPhase.done.name &&
        row.read<String?>('preview_error') == null) {
      try {
        final sources = ChatSnapshot.sources(
          row.read<String?>('preview_sources') ?? '[]',
          session.book,
        );
        final answer = ChatSnapshot.answer(
          row.read<String?>('preview_answer'),
          sources,
        );
        preview = answer?.blocks.firstOrNull?.text ?? preview;
      } on FormatException {
        // Corrupt history stays readable without showing its raw JSON.
      }
    }
    return ChatSnapshot.session(sessionRow, preview: preview);
  }

  Stream<List<ChatTurn>> watchTurns(int bookId, int sessionId) async* {
    await _ready();
    final query =
        _db.select(_db.chatTurns).join([
            innerJoin(
              _db.chatSessions,
              _db.chatSessions.id.equalsExp(_db.chatTurns.sessionId),
            ),
          ])
          ..where(
            _db.chatSessions.bookId.equals(bookId) &
                _db.chatSessions.id.equals(sessionId),
          )
          ..orderBy([OrderingTerm.asc(_db.chatTurns.sequence)]);
    yield* query.watch().map(
      (rows) => List.unmodifiable([
        for (final r in rows)
          ChatSnapshot.turn(
            r.readTable(_db.chatTurns),
            r.readTable(_db.chatSessions),
          ),
      ]),
    );
  }

  /// Current book identity for lifecycle invalidation; never starts a request.
  Stream<ChatBookRef?> watchBook(int bookId) =>
      (_db.select(_db.books)..where((b) => b.id.equals(bookId)))
          .watchSingleOrNull()
          .map(
            (b) => b == null
                ? null
                : (bookId: b.id, contentRevision: b.contentRevision),
          )
          .distinct();

  /// Local read only: no recovery, timestamps, progress, or network side effects.
  Stream<ChatSourceLocation?> watchSource(ChatSourceRef request) => _db
      .customSelect(
        'SELECT 1',
        readsFrom: {
          _db.books,
          _db.chapters,
          _db.paragraphs,
          _db.chatSessions,
          _db.chatTurns,
          _db.readingProgress,
        },
      )
      .watch()
      .asyncMap((_) => resolveSource(request));

  Future<ChatSourceLocation?> resolveSource(ChatSourceRef request) async {
    _open();
    return _db.transaction(() async {
      final session =
          await (_db.select(_db.chatSessions)..where(
                (s) =>
                    s.id.equals(request.sessionId) &
                    s.bookId.equals(request.bookId),
              ))
              .getSingleOrNull();
      final row =
          await (_db.select(_db.chatTurns)..where(
                (t) =>
                    t.id.equals(request.turnId) &
                    t.sessionId.equals(request.sessionId),
              ))
              .getSingleOrNull();
      if (session == null || row == null || row.attempt != request.attempt) {
        return null;
      }
      try {
        final turn = ChatSnapshot.turn(row, session, strict: true);
        final sources = ChatSnapshot.sources(row.sources, turn.book);
        final source = sources
            .where((s) => s.id == request.sourceId)
            .firstOrNull;
        if (source == null) return null;
        var blocks = <ChatAnswerBlock>[];
        if (turn.trustedHistory) {
          blocks = turn.answer!.blocks;
        } else if (turn.phase.isRunning) {
          blocks = (ChatPreviewDecoder(
            sources: sources,
          )..add(row.draft)).blocks;
        }
        var available = blocks.any(
          (b) => b.sources.any((s) => s.id == source.id),
        );
        try {
          await _book(turn.book);
          validateChatSources(
            [source],
            turn.book,
            await _paragraphs(turn.book, source.anchors),
          );
        } catch (_) {
          available = false;
        }
        final first = source.anchors.first, last = source.anchors.last;
        String? before, after, positionLabel;
        if (available) {
          final neighbors =
              await (_db.select(_db.paragraphs)..where(
                    (p) =>
                        p.chapterId.equals(first.chapterId) &
                        p.paragraphIndex.isIn([
                          first.paragraphIndex - 1,
                          last.paragraphIndex + 1,
                        ]),
                  ))
                  .get();
          before = neighbors
              .where((p) => p.paragraphIndex == first.paragraphIndex - 1)
              .firstOrNull
              ?.content;
          after = neighbors
              .where((p) => p.paragraphIndex == last.paragraphIndex + 1)
              .firstOrNull
              ?.content;
          final progress = await (_db.select(
            _db.readingProgress,
          )..where((p) => p.bookId.equals(request.bookId))).getSingleOrNull();
          if (progress != null) {
            final chapters = await (_db.select(
              _db.chapters,
            )..where((c) => c.bookId.equals(request.bookId))).get();
            final current = chapters
                .where((c) => c.id == progress.chapterId)
                .firstOrNull;
            final cited = chapters
                .where((c) => c.id == first.chapterId)
                .firstOrNull;
            if (current != null && cited != null) {
              if (current.id == cited.id &&
                  progress.paragraphIndex >= first.paragraphIndex &&
                  progress.paragraphIndex <= last.paragraphIndex) {
                positionLabel = 'Posisi baca lo sekarang';
              } else if (current.sortOrder > cited.sortOrder ||
                  current.id == cited.id &&
                      progress.paragraphIndex > last.paragraphIndex) {
                positionLabel = 'Udah lo baca';
              } else {
                positionLabel = 'Belum lo baca';
              }
            }
          }
        }
        _open();
        return ChatSourceLocation(
          source: source,
          available: available,
          generation: this,
          before: before,
          after: after,
          positionLabel: positionLabel,
        );
      } on FormatException {
        return null;
      }
    });
  }

  /// Nomor bab (urutan 1..n lewat sortOrder) per chapter id, buat chip sitasi.
  Future<Map<int, int>> chapterNumbers(int bookId) async {
    final rows =
        await (_db.select(_db.chapters)
              ..where((c) => c.bookId.equals(bookId))
              ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
            .get();
    return {for (var i = 0; i < rows.length; i++) rows[i].id: i + 1};
  }

  Stream<ChatSourceLocation?> watchQuote(ChatQuote quote) => _db
      .customSelect(
        'SELECT 1',
        readsFrom: {_db.books, _db.chapters, _db.paragraphs},
      )
      .watch()
      .asyncMap((_) => resolveQuote(quote));

  Future<ChatSourceLocation?> resolveQuote(ChatQuote quote) =>
      _db.transaction(() async {
        _open();
        try {
          final book = quote.anchors.first.book;
          await _book(book);
          final chapter =
              await (_db.select(_db.chapters)..where(
                    (c) =>
                        c.id.equals(quote.anchors.first.chapterId) &
                        c.bookId.equals(book.bookId),
                  ))
                  .getSingleOrNull();
          if (chapter == null) return null;
          final source = ChatSource(
            id: 'S1',
            chapterTitle: chapter.title,
            anchors: quote.anchors,
          );
          validateChatSources(
            [source],
            book,
            await _paragraphs(book, quote.anchors),
          );
          return ChatSourceLocation(
            source: source,
            available: true,
            generation: this,
          );
        } on FormatException {
          return null;
        } on StateError {
          return null;
        }
      });

  /// Validation and the explicit progress write share one transaction.
  Future<void> continueReading({ChatSourceRef? request, ChatQuote? quote}) =>
      _db.transaction(() async {
        if ((request == null) == (quote == null)) {
          throw ArgumentError('Satu sumber diperlukan');
        }
        final location = request != null
            ? await resolveSource(request)
            : await resolveQuote(quote!);
        if (location?.available != true) {
          throw StateError('Sumber ini udah gak tersedia');
        }
        _open();
        final anchor = location!.source.anchors.first;
        await _db
            .into(_db.readingProgress)
            .insertOnConflictUpdate(
              ReadingProgressCompanion.insert(
                bookId: Value(anchor.book.bookId),
                chapterId: anchor.chapterId,
                paragraphIndex: anchor.paragraphIndex,
                paragraphOffset: const Value(0),
                updatedAt: Value(_now()),
              ),
            );
      });

  Future<ChatSession?> sessionForQuote(ChatQuote quote) async {
    await _ready();
    final book = quote.anchors.first.book;
    await _book(book);
    final rows =
        await (_db.select(_db.chatTurns).join([
                innerJoin(
                  _db.chatSessions,
                  _db.chatSessions.id.equalsExp(_db.chatTurns.sessionId),
                ),
              ])
              ..where(
                _db.chatSessions.bookId.equals(book.bookId) &
                    _db.chatSessions.contentRevision.equals(
                      book.contentRevision,
                    ) &
                    _db.chatTurns.quote.isNotNull(),
              )
              ..orderBy([OrderingTerm.desc(_db.chatSessions.updatedAt)]))
            .get();
    final signature = jsonEncode([
      for (final a in quote.anchors) ChatSnapshot.anchorData(a),
    ]);
    for (final row in rows) {
      final session = row.readTable(_db.chatSessions);
      if (ChatSnapshot.session(session).invalid) continue;
      try {
        final saved = ChatSnapshot.quote(
          row.readTable(_db.chatTurns).quote,
          book,
        );
        if (saved != null &&
            jsonEncode([
                  for (final a in saved.anchors) ChatSnapshot.anchorData(a),
                ]) ==
                signature) {
          return ChatSnapshot.session(session);
        }
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  Future<ChatSession?> session(int bookId, int sessionId) async {
    await _ready();
    final row =
        await (_db.select(_db.chatSessions)
              ..where((s) => s.bookId.equals(bookId) & s.id.equals(sessionId)))
            .getSingleOrNull();
    return row == null ? null : ChatSnapshot.session(row);
  }

  Future<ChatSession?> lastOpenedSession(int bookId) async {
    await _ready();
    final row =
        await (_db.select(_db.chatSessions)
              ..where(
                (s) => s.bookId.equals(bookId) & s.lastOpenedAt.isNotNull(),
              )
              ..orderBy([
                (s) => OrderingTerm.desc(s.lastOpenedAt),
                (s) => OrderingTerm.desc(s.id),
              ])
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : ChatSnapshot.session(row);
  }

  Future<ChatSessionRow> _session(int bookId, int sessionId) async {
    final row =
        await (_db.select(_db.chatSessions)
              ..where((s) => s.bookId.equals(bookId) & s.id.equals(sessionId)))
            .getSingleOrNull();
    if (row == null) {
      throw StateError('Sesi bukan milik buku ini atau sudah dihapus');
    }
    return row;
  }

  Future<Book> _book(ChatBookRef ref) async {
    final row = await (_db.select(
      _db.books,
    )..where((b) => b.id.equals(ref.bookId))).getSingleOrNull();
    if (ref.bookId <= 0 ||
        ref.contentRevision <= 0 ||
        row == null ||
        row.contentRevision != ref.contentRevision) {
      throw StateError('Isi buku berubah atau buku sudah dihapus');
    }
    return row;
  }

  Future<ChatSessionRow> _writable(ChatBookRef book, int sessionId) async {
    await _book(book);
    final s = await _session(book.bookId, sessionId);
    if (s.contentRevision != book.contentRevision ||
        ChatSnapshot.session(s).invalid) {
      throw StateError('Sesi arsip/tidak valid hanya bisa dibaca');
    }
    return s;
  }

  void _model(String model, int promptVersion) {
    if (ChatSnapshot.text(model).trim().isEmpty || promptVersion <= 0) {
      throw const FormatException('Model atau versi prompt tidak valid');
    }
  }

  Future<void> _noPending(int sessionId) async {
    final running =
        await (_db.select(_db.chatTurns)
              ..where(
                (t) =>
                    t.sessionId.equals(sessionId) &
                    t.phase.isIn(
                      ChatPhase.values
                          .where((p) => p.isRunning)
                          .map((p) => p.name),
                    ),
              )
              ..limit(1))
            .getSingleOrNull();
    if (running != null) throw StateError('Masih ada jawaban yang diproses');
  }

  Future<Map<ChatParagraphRef, ChatParagraph>> _paragraphs(
    ChatBookRef book,
    Iterable<SourceAnchor> anchors,
  ) async {
    final requested = <int, Set<int>>{};
    for (final a in anchors) {
      if (a.book != book) throw const FormatException('Sumber dari buku lain');
      requested.putIfAbsent(a.chapterId, () => {}).add(a.paragraphIndex);
    }
    final result = <ChatParagraphRef, ChatParagraph>{};
    for (final entry in requested.entries) {
      final q =
          _db.select(_db.paragraphs).join([
            innerJoin(
              _db.chapters,
              _db.chapters.id.equalsExp(_db.paragraphs.chapterId),
            ),
          ])..where(
            _db.chapters.bookId.equals(book.bookId) &
                _db.paragraphs.chapterId.equals(entry.key) &
                _db.paragraphs.paragraphIndex.isIn(entry.value),
          );
      for (final r in await q.get()) {
        final p = r.readTable(_db.paragraphs);
        result[(chapterId: p.chapterId, paragraphIndex: p.paragraphIndex)] = (
          book: book,
          chapterId: p.chapterId,
          paragraphIndex: p.paragraphIndex,
          text: p.content,
        );
      }
    }
    return result;
  }

  Future<String?> _quote(ChatQuote? quote, ChatBookRef book) async {
    if (quote == null) return null;
    final raw = jsonEncode(ChatSnapshot.quoteData(quote));
    final decoded = ChatSnapshot.quote(raw, book)!;
    final paragraphs = await _paragraphs(book, decoded.anchors);
    for (final a in decoded.anchors) {
      final p = paragraphs[a.paragraph];
      if (p == null) throw const FormatException('Kutipan tidak ditemukan');
      a.validate(p, book);
    }
    return raw;
  }

  Future<ChatTurn> _insert(
    ChatSessionRow session,
    String question,
    String? quote, {
    required int sequence,
    required String model,
    required int promptVersion,
  }) async {
    _model(model, promptVersion);
    final at = _now();
    final id = await _db
        .into(_db.chatTurns)
        .insert(
          ChatTurnsCompanion.insert(
            sessionId: session.id,
            sequence: sequence,
            question: question,
            quote: Value(quote),
            phase: ChatPhase.preparing.name,
            model: model,
            promptVersion: promptVersion,
            createdAt: Value(at),
            updatedAt: Value(at),
          ),
        );
    await (_db.update(_db.chatSessions)..where((s) => s.id.equals(session.id)))
        .write(ChatSessionsCompanion(updatedAt: Value(at)));
    return ChatSnapshot.turn(
      await (_db.select(
        _db.chatTurns,
      )..where((t) => t.id.equals(id))).getSingle(),
      session,
      strict: true,
    );
  }

  /// Tidak ada sesi kosong: session + first turn berada dalam transaksi.
  Future<ChatTurn> createFirstTurn(
    ChatBookRef book, {
    required String question,
    required String model,
    required int promptVersion,
    ChatQuote? quote,
  }) async {
    await _ready();
    final q = chatQuestion(question);
    return _db.transaction(() async {
      await _book(book);
      final quoted = await _quote(quote, book);
      final at = _now();
      final id = await _db
          .into(_db.chatSessions)
          .insert(
            ChatSessionsCompanion.insert(
              bookId: book.bookId,
              contentRevision: book.contentRevision,
              title: chatTitle(q, automatic: true),
              createdAt: Value(at),
              updatedAt: Value(at),
              lastOpenedAt: Value(at),
            ),
          );
      return _insert(
        await _session(book.bookId, id),
        q,
        quoted,
        sequence: 0,
        model: model,
        promptVersion: promptVersion,
      );
    });
  }

  Future<ChatTurn> appendTurn(
    ChatBookRef book,
    int sessionId, {
    required String question,
    required String model,
    required int promptVersion,
    ChatQuote? quote,
  }) async {
    await _ready();
    final q = chatQuestion(question);
    return _db.transaction(() async {
      final s = await _writable(book, sessionId);
      await _noPending(sessionId);
      final last =
          await (_db.select(_db.chatTurns)
                ..where((t) => t.sessionId.equals(sessionId))
                ..orderBy([(t) => OrderingTerm.desc(t.sequence)])
                ..limit(1))
              .getSingleOrNull();
      return _insert(
        s,
        q,
        await _quote(quote, book),
        sequence: (last?.sequence ?? -1) + 1,
        model: model,
        promptVersion: promptVersion,
      );
    });
  }

  /// Explicit continuation creates a new turn; paid answers remain immutable.
  Future<ChatTurn> continueExploration(
    ChatTurn previous, {
    required String model,
  }) async {
    await _ready();
    return _db.transaction(() async {
      final session = await _writable(previous.book, previous.sessionId);
      await _noPending(session.id);
      final last =
          await (_db.select(_db.chatTurns)
                ..where((t) => t.sessionId.equals(session.id))
                ..orderBy([(t) => OrderingTerm.desc(t.sequence)])
                ..limit(1))
              .getSingle();
      final current = ChatSnapshot.turn(last, session, strict: true);
      if (current.id != previous.id ||
          !chatCanContinue(current) ||
          current.model != model ||
          current.promptVersion != chatPromptVersion) {
        throw const FormatException(
          'Checkpoint kedaluwarsa. Kirim pertanyaan baru untuk mulai ulang.',
        );
      }
      final turn = await _insert(
        session,
        current.question,
        await _quote(current.quote, current.book),
        sequence: current.sequence + 1,
        model: model,
        promptVersion: chatPromptVersion,
      );
      await (_db.update(
        _db.chatTurns,
      )..where((t) => t.id.equals(turn.id))).write(
        ChatTurnsCompanion(
          exploration: Value(
            ChatExploration.parse(current.exploration!)
                .forTurn(turn.id)
                .encode(),
          ),
        ),
      );
      return ChatSnapshot.turn(
        await (_db.select(
          _db.chatTurns,
        )..where((t) => t.id.equals(turn.id))).getSingle(),
        session,
        strict: true,
      );
    });
  }

  Future<bool> validateRetrieval(
    ChatAttemptRef ref,
    List<ChatSource> sources,
  ) async {
    if (!await _callbackReady()) return false;
    return _db.transaction(() async {
      final owned = await _guard(ref);
      if (owned == null ||
          ![
            ChatPhase.preparing.name,
            ChatPhase.retrieving.name,
          ].contains(owned.turn.phase)) {
        return false;
      }
      validateChatSources(
        sources,
        ref.book,
        await _paragraphs(ref.book, sources.expand((s) => s.anchors)),
      );
      return !_disposed;
    });
  }

  Future<bool> saveExploration(
    ChatAttemptRef ref,
    ChatExploration exploration, {
    List<ChatSource> evidence = const [],
  }) async {
    if (!await _callbackReady()) return false;
    return _db.transaction(() async {
      final owned = await _guard(ref);
      if (owned == null ||
          ![
            ChatPhase.preparing.name,
            ChatPhase.retrieving.name,
          ].contains(owned.turn.phase)) {
        return false;
      }
      if (exploration.book != ref.book ||
          exploration.sessionId != ref.sessionId ||
          exploration.turnId != ref.turnId ||
          exploration.question != owned.turn.question ||
          exploration.model != owned.turn.model) {
        throw const FormatException('Checkpoint bukan milik attempt ini');
      }
      validateChatSources(
        evidence,
        ref.book,
        await _paragraphs(ref.book, evidence.expand((s) => s.anchors)),
      );
      if (owned.turn.exploration != null) {
        final before = ChatExploration.parse(owned.turn.exploration!);
        if (before.manifest != exploration.manifest ||
            before.cursor > exploration.cursor) {
          throw const FormatException(
            'Checkpoint tidak boleh mundur/berganti isi',
          );
        }
      }
      final raw = exploration.encode();
      ChatExploration.parse(raw);
      if (_disposed) return false;
      await (_db.update(
        _db.chatTurns,
      )..where((t) => t.id.equals(ref.turnId))).write(
        ChatTurnsCompanion(exploration: Value(raw), updatedAt: Value(_now())),
      );
      return true;
    });
  }

  Future<void> rename(ChatBookRef book, int sessionId, String title) async {
    await _ready();
    final value = chatTitle(title);
    await _db.transaction(() async {
      await _writable(book, sessionId);
      await (_db.update(
        _db.chatSessions,
      )..where((s) => s.id.equals(sessionId))).write(
        ChatSessionsCompanion(
          title: Value(value),
          manualTitle: const Value(true),
          updatedAt: Value(_now()),
        ),
      );
    });
  }

  /// Membuka arsip tetap boleh; tidak mengubah isi sesi.
  Future<void> markOpened(int bookId, int sessionId) async {
    await _ready();
    await _db.transaction(() async {
      await _session(bookId, sessionId);
      await (_db.update(_db.chatSessions)..where((s) => s.id.equals(sessionId)))
          .write(ChatSessionsCompanion(lastOpenedAt: Value(_now())));
    });
  }

  Future<void> saveScrollAnchor(
    int bookId,
    int sessionId,
    ChatScrollAnchor? anchor,
  ) async {
    await _ready();
    await _db.transaction(() async {
      await _session(bookId, sessionId);
      String? raw;
      if (anchor != null) {
        raw = jsonEncode(ChatSnapshot.scrollData(anchor));
        ChatSnapshot.scroll(raw);
        final t =
            await (_db.select(_db.chatTurns)..where(
                  (t) =>
                      t.id.equals(anchor.turnId) &
                      t.sessionId.equals(sessionId),
                ))
                .getSingleOrNull();
        if (t == null) throw const FormatException('Posisi dari sesi lain');
      }
      await (_db.update(_db.chatSessions)..where((s) => s.id.equals(sessionId)))
          .write(ChatSessionsCompanion(scrollAnchor: Value(raw)));
    });
  }

  Future<ChatSession?> deleteSession(int bookId, int sessionId) async {
    await _ready();
    await _db.transaction(() async {
      await _session(bookId, sessionId);
      await (_db.delete(
        _db.chatSessions,
      )..where((s) => s.id.equals(sessionId))).go();
    });
    _pending.removeWhere((ref, _) => ref.sessionId == sessionId);
    return lastOpenedSession(bookId);
  }

  Future<ChatTurn> retry(
    ChatAttemptRef ref, {
    required String model,
    required int promptVersion,
  }) async {
    await _ready();
    _model(model, promptVersion);
    return _db.transaction(() async {
      final s = await _writable(ref.book, ref.sessionId);
      final row =
          await (_db.select(_db.chatTurns)..where(
                (t) =>
                    t.id.equals(ref.turnId) & t.sessionId.equals(ref.sessionId),
              ))
              .getSingle();
      if (row.attempt != ref.attempt) throw StateError('Attempt sudah diganti');
      await _noPending(s.id);
      final last =
          await (_db.select(_db.chatTurns)
                ..where((t) => t.sessionId.equals(s.id))
                ..orderBy([(t) => OrderingTerm.desc(t.sequence)])
                ..limit(1))
              .getSingle();
      final previous = ChatSnapshot.turn(row, s, strict: true);
      await _quote(previous.quote, ref.book);
      final next = previous.retry(
        current: ref.book,
        isLatest: last.id == row.id,
        at: _now(),
        model: model,
        promptVersion: promptVersion,
      );
      await (_db.update(
        _db.chatTurns,
      )..where((t) => t.id.equals(row.id))).write(
        ChatTurnsCompanion(
          attempt: Value(next.attempt),
          phase: Value(next.phase.name),
          model: Value(model),
          promptVersion: Value(promptVersion),
          updatedAt: Value(next.updatedAt),
          draft: const Value(''),
          answer: const Value(null),
          sources: const Value('[]'),
          exploration: Value(
            row.model == model && row.promptVersion == promptVersion
                ? row.exploration
                : null,
          ),
          error: const Value(null),
          httpStatus: const Value(null),
        ),
      );
      await (_db.update(_db.chatSessions)
            ..where((s) => s.id.equals(ref.sessionId)))
          .write(ChatSessionsCompanion(updatedAt: Value(next.updatedAt)));
      _pending.remove(ref);
      return next;
    });
  }

  Future<({ChatSessionRow session, ChatTurnRow turn})?> _guard(
    ChatAttemptRef ref,
  ) async {
    if (_disposed) return null;
    final q =
        _db.select(_db.chatTurns).join([
          innerJoin(
            _db.chatSessions,
            _db.chatSessions.id.equalsExp(_db.chatTurns.sessionId),
          ),
          innerJoin(_db.books, _db.books.id.equalsExp(_db.chatSessions.bookId)),
        ])..where(
          _db.chatTurns.id.equals(ref.turnId) &
              _db.chatSessions.id.equals(ref.sessionId) &
              _db.chatSessions.bookId.equals(ref.book.bookId) &
              _db.chatSessions.contentRevision.equals(
                ref.book.contentRevision,
              ) &
              _db.books.contentRevision.equals(ref.book.contentRevision),
        );
    final row = await q.getSingleOrNull();
    if (_disposed || row == null) {
      _pending.remove(ref);
      return null;
    }
    final s = row.readTable(_db.chatSessions), t = row.readTable(_db.chatTurns);
    if (ChatSnapshot.session(s).invalid ||
        !ChatSnapshot.turn(t, s).accepts(ref, ref.book)) {
      _pending.remove(ref);
      return null;
    }
    return (session: s, turn: t);
  }

  /// Freeze the exact evidence before transport begins; cannot replace mid-stream.
  Future<bool> prepareSources(
    ChatAttemptRef ref,
    List<ChatSource> sources,
  ) async {
    if (!await _callbackReady()) return false;
    return _db.transaction(() async {
      final owned = await _guard(ref);
      if (owned == null ||
          ![
            ChatPhase.preparing.name,
            ChatPhase.retrieving.name,
          ].contains(owned.turn.phase)) {
        return false;
      }
      final raw = jsonEncode(ChatSnapshot.sourcesData(sources));
      final decoded = ChatSnapshot.sources(raw, ref.book);
      final t = ChatSnapshot.turn(owned.turn, owned.session, strict: true);
      final p = await _paragraphs(ref.book, [
        ...decoded.expand((s) => s.anchors),
        ...?t.quote?.anchors,
      ]);
      final b = await _book(ref.book);
      buildChatPrompt(
        session: ChatSnapshot.session(owned.session),
        current: ref.book,
        question: t.question,
        beforeSequence: t.sequence,
        history: [],
        sources: decoded,
        paragraphs: p,
        title: b.title,
        author: b.author,
        quote: t.quote,
      );
      if (_disposed) return false;
      await (_db.update(
        _db.chatTurns,
      )..where((t) => t.id.equals(ref.turnId))).write(
        ChatTurnsCompanion(
          sources: Value(raw),
          phase: const Value('waiting'),
          updatedAt: Value(_now()),
        ),
      );
      return true;
    });
  }

  /// Recheck the frozen attempt before network and before exposing live citations.
  Future<bool> validatePrepared(
    ChatAttemptRef ref,
    List<ChatSource> sources,
  ) async {
    if (!await _callbackReady()) return false;
    return _db.transaction(() async {
      final owned = await _guard(ref);
      if (owned == null ||
          ![
            ChatPhase.waiting.name,
            ChatPhase.writing.name,
            ChatPhase.slow.name,
          ].contains(owned.turn.phase)) {
        return false;
      }
      final raw = jsonEncode(ChatSnapshot.sourcesData(sources));
      if (owned.turn.sources != raw) return false;
      validateChatSources(
        sources,
        ref.book,
        await _paragraphs(ref.book, sources.expand((s) => s.anchors)),
      );
      return !_disposed;
    });
  }

  /// True = accepted (possibly buffered). Cumulative drafts must never shrink.
  /// At most one write/500ms unless ≥1KiB grew or phase changed; no token timers.
  Future<bool> checkpoint(
    ChatAttemptRef ref, {
    required String draft,
    required ChatPhase phase,
  }) async {
    if (!await _callbackReady()) return false;
    ChatSnapshot.text(draft);
    if (!phase.isRunning) {
      throw ArgumentError('Gunakan finalize untuk terminal state');
    }
    return _db.transaction(() async {
      final owned = await _guard(ref);
      if (owned == null) return false;
      final before = ChatPhase.restore(owned.turn.phase);
      if (phase == ChatPhase.preparing ||
          phase == ChatPhase.waiting && before != ChatPhase.waiting ||
          phase == ChatPhase.retrieving &&
              ![ChatPhase.preparing, ChatPhase.retrieving].contains(before) ||
          phase != ChatPhase.retrieving &&
              ![
                ChatPhase.waiting,
                ChatPhase.writing,
                ChatPhase.slow,
              ].contains(before) ||
          phase == ChatPhase.retrieving && draft.isNotEmpty) {
        return false;
      }
      final pending = _pending[ref];
      if (!draft.startsWith(pending?.draft ?? owned.turn.draft)) return false;
      final at = _now(), bytes = utf8.encode(draft).length;
      final due =
          pending == null ||
          phase != pending.phase ||
          at.difference(pending.writtenAt) >=
              const Duration(milliseconds: 500) ||
          bytes - pending.writtenBytes >= 1024;
      _pending[ref] = _Checkpoint(
        draft,
        phase,
        due ? at : pending.writtenAt,
        due ? bytes : pending.writtenBytes,
      );
      if (!due) return true;
      await (_db.update(
        _db.chatTurns,
      )..where((t) => t.id.equals(ref.turnId))).write(
        ChatTurnsCompanion(
          draft: Value(draft),
          phase: Value(phase.name),
          updatedAt: Value(at),
        ),
      );
      await (_db.update(_db.chatSessions)
            ..where((s) => s.id.equals(ref.sessionId)))
          .write(ChatSessionsCompanion(updatedAt: Value(at)));
      return true;
    });
  }

  Future<bool> finalize(
    ChatAttemptRef ref, {
    required ChatPhase phase,
    String? draft,
    ChatAnswer? answer,
    AiError? error,
    int? httpStatus,
    List<ChatStep>? steps,
  }) async {
    if (!await _callbackReady()) return false;
    if (phase.isRunning) throw ArgumentError('Terminal state wajib');
    if ((phase == ChatPhase.done) != (answer != null) ||
        phase == ChatPhase.done && error != null ||
        phase == ChatPhase.failed && error == null ||
        httpStatus != null && (httpStatus < 100 || httpStatus > 599)) {
      throw const FormatException('Hasil akhir tidak konsisten');
    }
    return _db.transaction(() async {
      final owned = await _guard(ref);
      if (owned == null) return false;
      final latest = _pending[ref]?.draft ?? owned.turn.draft;
      final text = ChatSnapshot.text(draft ?? latest);
      if (!text.startsWith(latest)) return false;
      String? raw;
      if (answer != null) {
        final evidence = ChatSnapshot.sources(owned.turn.sources, ref.book);
        final byId = {
          for (final s in evidence)
            s.id: jsonEncode(ChatSnapshot.sourcesData([s])),
        };
        for (final b in answer.blocks) {
          for (final s in b.sources) {
            if (byId[s.id] != jsonEncode(ChatSnapshot.sourcesData([s]))) {
              throw const FormatException(
                'Jawaban memakai sumber di luar attempt',
              );
            }
          }
        }
        validateChatSources(
          evidence,
          ref.book,
          await _paragraphs(ref.book, evidence.expand((s) => s.anchors)),
        );
        raw = jsonEncode(ChatSnapshot.answerData(answer));
        ChatSnapshot.answer(raw, evidence);
      }
      if (_disposed) return false;
      final at = _now();
      await (_db.update(
        _db.chatTurns,
      )..where((t) => t.id.equals(ref.turnId))).write(
        ChatTurnsCompanion(
          phase: Value(phase.name),
          draft: Value(text),
          answer: Value(raw),
          error: Value(error?.name),
          httpStatus: Value(httpStatus),
          steps: Value(
            steps == null || steps.isEmpty ? null : encodeChatSteps(steps),
          ),
          updatedAt: Value(at),
        ),
      );
      await (_db.update(_db.chatSessions)
            ..where((s) => s.id.equals(ref.sessionId)))
          .write(ChatSessionsCompanion(updatedAt: Value(at)));
      _pending.remove(ref);
      return true;
    });
  }
}

class _Checkpoint {
  const _Checkpoint(this.draft, this.phase, this.writtenAt, this.writtenBytes);
  final String draft;
  final ChatPhase phase;
  final DateTime writtenAt;
  final int writtenBytes;
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final repo = ChatRepository(ref.watch(appDatabaseProvider));
  ref.onDispose(repo.dispose);
  return repo;
});
