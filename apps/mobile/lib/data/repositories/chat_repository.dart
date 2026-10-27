import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/chat_prompt.dart';
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
          'SELECT s.*, (SELECT question FROM chat_turns t WHERE t.session_id = s.id '
          'ORDER BY sequence DESC LIMIT 1) AS preview FROM chat_sessions s '
          'WHERE s.book_id = ? ORDER BY s.updated_at DESC, s.id DESC',
          variables: [Variable.withInt(bookId)],
          readsFrom: {_db.chatSessions, _db.chatTurns},
        )
        .watch()
        .map(
          (rows) => List.unmodifiable([
            for (final r in rows)
              ChatSnapshot.session(
                _db.chatSessions.map(r.data),
                preview: r.read<String?>('preview'),
              ),
          ]),
        );
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
