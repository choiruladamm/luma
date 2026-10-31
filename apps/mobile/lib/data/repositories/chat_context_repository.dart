import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/chat_steps.dart';
import '../../domain/chat_budget.dart';
import '../../domain/chat_prompt.dart';
import '../../domain/chat_exploration.dart';
import '../../domain/chat_retrieval.dart';
import '../../domain/chat_toc.dart';
import '../../domain/models/ai_model.dart';
import '../../domain/models/ai_reply.dart';
import '../../domain/models/book_chat.dart';
import '../database/app_database.dart';
import '../services/api_key_store.dart';
import '../services/openrouter_service.dart';
import 'chat_repository.dart';
import 'chat_index_repository.dart';
import 'chat_notes_repository.dart';
import 'chat_snapshot.dart';

/// Token + waktu yang disisakan untuk jawaban akhir sebelum putaran baru.
const chatAnswerReserveTokens = 40000;
const chatAnswerReserveTime = Duration(seconds: 45);

/// Perbaikan otomatis maksimal per kiriman untuk output jawaban yang invalid.
const chatMaxRepairs = 2;

/// Each send reads credentials afresh. Document vectors survive in the local DB.
class ChatContextRepository {
  ChatContextRepository(
    this._db,
    this._chat,
    this._router,
    this._keys, {
    this.tokenBudget = chatQuestionTokens,
    this.deadline = chatQuestionDeadline,
  });

  /// Budget per kiriman; test memakai angka kecil untuk memaksa partial.
  final int tokenBudget;
  final Duration deadline;
  final AppDatabase _db;
  final ChatRepository _chat;
  final OpenRouterService _router;
  final ApiKeyStore _keys;
  late final _notes = ChatNotesRepository(_db);
  Future<void> _indexTail = Future.value();
  ChatIndexKey? _indexKey;
  String? _manifest;
  List<Float32List>? _documents;
  final _models = <String, ChatModelInfo>{};
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    _documents = null;
    _indexKey = null;
    _manifest = null;
  }

  void _check(CancelToken? cancel) {
    if (_disposed) throw StateError('Konteks chat sudah ditutup');
    if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
  }

  /// For #118 first-send/retry: capture this model when creating the turn.
  Future<String> model() async {
    final row = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals('ai.model'))).getSingleOrNull();
    return row?.value ?? defaultAiModel;
  }

  /// Context window dari provider (gratis), di-cache per model selama hidup
  /// repository; gagal → fallback konservatif yang tercatat di ledger.
  Future<ChatModelInfo> _modelInfo(String model, CancelToken? cancel) async {
    final cached = _models[model];
    if (cached != null) return cached;
    final info = await _router.modelInfo(model, cancel: cancel);
    _check(cancel);
    if (info == null) {
      return (
        id: model,
        contextTokens: chatFallbackContextTokens,
        fromProvider: false,
      );
    }
    return _models[model] = info;
  }

  /// Document batches may be cached before evidence is frozen. A stale attempt
  /// never sends an answer. Caller owns checkpoint/finalize and stop lifecycle.
  /// [readingChapterId] = bab yang sedang dibaca saat masuk chat, hanya untuk
  /// menyelesaikan rujukan "bab ini"/"bab III"; bukan sumber fakta.
  Future<PreparedChat?> prepare(
    ChatTurn target, {
    CancelToken? cancel,
    int? readingChapterId,
    void Function(int completed, int total)? onIndexProgress,
    void Function(ChatExplorationProgress progress)? onExplorationProgress,
    bool Function()? answerNow,
    void Function(ChatStep step)? onStep,
  }) async {
    _check(cancel);
    final key = await _keys.read();
    _check(cancel);
    if (key == null || key.trim().isEmpty) {
      throw const AiException(AiError.noApiKey);
    }
    await _chat.recoverInterrupted();
    _check(cancel);
    try {
      final input = await _db.transaction(() async {
        final sessionRow =
            await (_db.select(_db.chatSessions)..where(
                  (s) =>
                      s.id.equals(target.sessionId) &
                      s.bookId.equals(target.book.bookId),
                ))
                .getSingleOrNull();
        final b = await (_db.select(
          _db.books,
        )..where((b) => b.id.equals(target.book.bookId))).getSingleOrNull();
        if (sessionRow == null ||
            b == null ||
            b.contentRevision != target.book.contentRevision) {
          return null;
        }
        final session = ChatSnapshot.session(sessionRow);
        if (session.invalid || session.book != target.book) return null;
        final rows =
            await (_db.select(_db.chatTurns)
                  ..where((t) => t.sessionId.equals(session.id))
                  ..orderBy([(t) => OrderingTerm.asc(t.sequence)]))
                .get();
        final turns = rows
            .map((t) => ChatSnapshot.turn(t, sessionRow))
            .toList();
        final matches = turns.where((t) => t.id == target.id).toList();
        if (matches.isEmpty ||
            !matches.single.accepts(target.attemptRef, session.book) ||
            ![
              ChatPhase.preparing,
              ChatPhase.retrieving,
            ].contains(matches.single.phase)) {
          return null;
        }
        final turn = matches.single;
        final selectedModel = await model();
        if (turn.model != selectedModel ||
            turn.promptVersion != chatPromptVersion) {
          throw const FormatException(
            'Model/prompt berubah; mulai ulang attempt secara eksplisit',
          );
        }
        final chapterRows =
            await (_db.select(_db.chapters)
                  ..where((c) => c.bookId.equals(b.id))
                  ..orderBy([
                    (c) => OrderingTerm.asc(c.sortOrder),
                    (c) => OrderingTerm.asc(c.id),
                  ]))
                .get();
        final query =
            _db.select(_db.paragraphs).join([
                innerJoin(
                  _db.chapters,
                  _db.chapters.id.equalsExp(_db.paragraphs.chapterId),
                ),
              ])
              ..where(_db.chapters.bookId.equals(b.id))
              ..orderBy([
                OrderingTerm.asc(_db.chapters.sortOrder),
                OrderingTerm.asc(_db.chapters.id),
                OrderingTerm.asc(_db.paragraphs.paragraphIndex),
              ]);
        final indexed = <ChatIndexedParagraph>[];
        final paragraphs = <ChatParagraphRef, ChatParagraph>{};
        final chars = <int, int>{};
        for (final row in await query.get()) {
          final p = row.readTable(_db.paragraphs),
              c = row.readTable(_db.chapters);
          final ChatParagraph paragraph = (
            book: session.book,
            chapterId: c.id,
            paragraphIndex: p.paragraphIndex,
            text: p.content,
          );
          paragraphs[(chapterId: c.id, paragraphIndex: p.paragraphIndex)] =
              paragraph;
          chars[c.id] = (chars[c.id] ?? 0) + p.content.length;
          indexed.add((
            paragraph: paragraph,
            chapterTitle: c.title,
            groupIndex: p.groupIndex,
          ));
        }
        final toc = <ChatChapterInfo>[
          for (final c in chapterRows)
            if (chars.containsKey(c.id))
              (
                id: c.id,
                title: c.title,
                section: c.section,
                chars: chars[c.id]!,
              ),
        ];
        final chunks = chatChunks(indexed, session.book);
        final quoted = chatQuoteSources(chunks, turn.quote);
        // Validate quote coverage, question, history and actual system budget
        // before any paid request. Final selected sources get the same checks.
        final preflight = buildChatPrompt(
          session: session,
          current: session.book,
          question: turn.question,
          beforeSequence: turn.sequence,
          history: turns,
          sources: quoted,
          paragraphs: paragraphs,
          title: b.title,
          author: b.author,
          quote: turn.quote,
        );
        return (
          session: session,
          turn: turn,
          book: b,
          toc: toc,
          chunks: chunks,
          windows: chatGlobalWindows(indexed),
          paragraphs: paragraphs,
          history: turns,
          quoted: quoted,
          preflight: preflight,
        );
      });
      _check(cancel);
      if (input == null) return null;
      final budget = ChatBudget(
        model: await _modelInfo(input.turn.model, cancel),
        tokens: tokenBudget,
        deadline: deadline,
      );
      Future<bool> guard() => _chat.validateRetrieval(target.attemptRef, []);
      final current = input.session.book;
      final toc = input.toc;
      // Jawaban akhir harus muat context model: sumber dan history mengikuti.
      final answerInput = [
        chatPromptBytes,
        budget.inputBytesFor(chatAnswerMaxTokens),
      ].reduce((a, b) => a < b ? a : b);
      final sourceBudget =
          (answerInput - utf8.encode(chatAnswerSystemPrompt).length - 6000)
              .clamp(0, chatSourceBytes);
      final tocById = {for (final c in toc) c.id: c};
      final history =
          ((jsonDecode(input.preflight.user) as Map)['history'] as List)
              .map((h) => Map<String, String>.from(h as Map))
              .toList();
      final quote = input.turn.quote;
      final reading = readingChapterId == null
          ? null
          : tocById[readingChapterId];
      final planUser = chatRetrievalUser(
        {
          'question': input.turn.question,
          'history': history,
          if (quote != null) 'selectedQuote': quote.text,
          'book': {
            'title': input.book.title,
            'author': input.book.author ?? '',
          },
          'toc': chatTocData(toc),
          if (reading != null)
            'readingPosition': {
              'chapterId': reading.id,
              'label': chatChapterLabel(reading),
            },
        },
        chatPlanSystem,
        budget.inputBytesFor(600),
      );
      // English subqueries resolve history/quote; keep the original query small.
      final original = chatEmbeddingQuery(
        input.turn.question,
        const [],
        null,
        ChatEmbeddingModel.qwen8b,
      );
      final saved = input.turn.exploration == null
          ? null
          : ChatExploration.parse(input.turn.exploration!);
      // Urutan [ids] = urutan baca (bab dari cache di depan, #151).
      List<ChatSource> scopedWindows(List<int> ids) {
        final scoped = [
          for (final id in ids)
            for (final w in input.windows)
              if (w.anchors.first.chapterId == id) w,
        ];
        return [
          for (final (i, w) in scoped.indexed)
            ChatSource(
              id: 'S${i + 1}',
              chapterTitle: w.chapterTitle,
              anchors: w.anchors,
            ),
        ];
      }

      if (saved != null) {
        saved.validate(
          input.turn,
          saved.strategy.reads ? scopedWindows(saved.chapterIds) : input.chunks,
        );
      }
      final rawPlan = saved == null
          ? parseChatQueryPlan(
              await _complete(
                key,
                input.turn.model,
                chatPlanSystem,
                planUser,
                600,
                cancel,
                budget,
                guard,
              ),
              knownChapterIds: tocById.keys,
            )
          : ChatQueryPlan(
              englishQuery: saved.query,
              needsClarification: false,
              strategy: saved.strategy,
              queries: saved.pendingQueries,
              chapterIds: saved.chapterIds,
            );
      _check(cancel);
      // Nomor bab yang ada di beberapa Book tidak boleh ditebak model.
      final ambiguous = rawPlan.strategy == ChatSearchStrategy.chapters
          ? chatAmbiguousSections(
              input.turn.question,
              rawPlan.chapterIds,
              toc,
              readingChapterId: reading?.id,
            )
          : const <String>[];
      final plan = ambiguous.isEmpty
          ? rawPlan
          : ChatQueryPlan(
              englishQuery: rawPlan.englishQuery,
              needsClarification: true,
              strategy: ChatSearchStrategy.chapters,
              clarification:
                  'Maksud lo bab yang di ${ambiguous.join(', ')} yang mana?',
            );
      var selected = input.quoted;
      ChatExploration? exploration;
      var noteSourceIds = <String, String>{};
      var cachedChapterCount = 0;
      // Bab isi = semua bab minus front/back matter dari planner (skip_ids);
      // subset chapter_ids eksplisit tetap dihormati.
      final content = [
        for (final c in toc)
          if (!plan.skipIds.contains(c.id)) c.id,
      ];
      final requested =
          plan.strategy == ChatSearchStrategy.global && plan.chapterIds.isEmpty
          ? content
          : plan.chapterIds;
      String labelOfId(int id) {
        final c = tocById[id];
        return c == null ? 'bab $id' : chatChapterLabel(c);
      }

      String labelsOf(List<int> ids) => [
        ...ids.take(4).map(labelOfId),
        if (ids.length > 4) '+${ids.length - 4} lagi',
      ].join(', ');
      // Langkah AI (#153): dicatat tanpa request tambahan.
      if (plan.needsClarification) {
        onStep?.call(ChatStep.plan('tanya balik dulu'));
      } else if (plan.strategy == ChatSearchStrategy.offTopic) {
        onStep?.call(ChatStep.plan('ngobrol tanpa buka buku'));
      } else if (plan.strategy.reads) {
        onStep?.call(
          requested.length == content.length &&
                  plan.strategy == ChatSearchStrategy.global
              ? ChatStep.plan('baca seluruh buku, ${requested.length} bab')
              : ChatStep.plan(
                  'baca ${requested.length} bab',
                  detail: labelsOf(requested),
                ),
        );
      } else {
        onStep?.call(ChatStep.plan('cari di buku'));
      }
      if (!plan.needsClarification &&
          plan.strategy != ChatSearchStrategy.chapters &&
          plan.strategy != ChatSearchStrategy.offTopic &&
          plan.skipIds.isNotEmpty) {
        onStep?.call(ChatStep.skip(labelsOf(plan.skipIds)));
      }
      if (!plan.needsClarification &&
          plan.strategy.reads &&
          scopedWindows(requested).isNotEmpty) {
        // Seluruh buku: bab yang catatannya masih cocok di cache tidak dibaca
        // ulang; urutan baca menaruh bab cache di depan supaya cursor tetap
        // prefix. Continuation memakai urutan yang tersimpan di checkpoint.
        final chapterManifests = <int, String>{
          for (final id in requested)
            id: chatWindowManifest(scopedWindows([id])),
        };
        final cache =
            saved == null && plan.strategy == ChatSearchStrategy.global
            ? await _notes.load(current, chapterManifests)
            : const <int, List<ChatCachedNote>>{};
        _check(cancel);
        final chapterIds =
            saved?.chapterIds ??
            [
              for (final id in requested)
                if (cache.containsKey(id)) id,
              for (final id in requested)
                if (!cache.containsKey(id)) id,
            ];
        final windows = scopedWindows(chapterIds);
        final cachedNotes = <ChatExplorationNote>[];
        var cachedWindows = 0;
        for (final id in chapterIds) {
          final notes = cache[id];
          if (notes == null) continue;
          cachedChapterCount++;
          cachedWindows += windows
              .where((w) => w.anchors.first.chapterId == id)
              .length;
          cachedNotes.addAll(chatNotesFromCache(id, notes, windows));
        }
        if (cachedChapterCount > 0) {
          onStep?.call(ChatStep.cache(cachedChapterCount));
        }
        final cachedIds = cache.keys.toSet();
        final windowsById = {for (final w in windows) w.id: w};
        final chapterLastIndex = <int, int>{
          for (final (i, w) in windows.indexed) w.anchors.first.chapterId: i,
        };
        final globalQuotes = <ChatSource>[];
        for (final (i, source) in input.quoted.indexed) {
          final matches = windows.where(
            (w) => _rangeKey(w) == _rangeKey(source),
          );
          globalQuotes.add(
            matches.isNotEmpty
                ? matches.first
                : ChatSource(
                    id: 'S${windows.length + i + 1}',
                    chapterTitle: source.chapterTitle,
                    anchors: source.anchors,
                  ),
          );
        }
        ChatExploration checkpoint({
          required int cursor,
          required List<ChatExplorationNote> notes,
          String? stopReason,
        }) => ChatExploration(
          book: current,
          sessionId: target.sessionId,
          turnId: target.id,
          question: target.question,
          model: target.model,
          manifest: chatWindowManifest(windows),
          query: plan.englishQuery,
          cursor: cursor,
          total: windows.length,
          notes: notes,
          strategy: plan.strategy,
          chapterIds: chapterIds,
          stopReason: stopReason,
        );
        var work =
            saved ?? checkpoint(cursor: cachedWindows, notes: cachedNotes);
        final notesSystem = plan.strategy == ChatSearchStrategy.global
            ? chatOverviewSystem
            : chatGlobalSystem;
        String? labelOf(List<ChatSource> batch) {
          final c = tocById[batch.first.anchors.first.chapterId];
          return c == null ? null : chatChapterLabel(c);
        }

        void progress(ChatExploration state, {String? label}) =>
            onExplorationProgress?.call((
              completed: state.cursor,
              total: state.total,
              label: label,
              notes: state.notes,
            ));
        // Direct read: a requested chapter that fits the answer budget is sent
        // as original text, without lossy notes.
        final direct =
            saved == null && plan.strategy == ChatSearchStrategy.chapters
            ? chatSplitLargeSources(
                chatPackGlobalSources([...globalQuotes, ...windows]),
                sourceBudget ~/ 3,
              )
            : null;
        if (direct != null &&
            fitChatSources(direct, maxBytes: sourceBudget).length ==
                direct.length) {
          work = checkpoint(cursor: windows.length, notes: []);
          if (!await _chat.saveExploration(
            target.attemptRef,
            work,
            evidence: windows,
          )) {
            return null;
          }
          progress(work);
          for (final id in chapterIds) {
            onStep?.call(ChatStep.read(labelOfId(id), detail: 'teks asli'));
          }
          selected = direct;
          exploration = work;
        } else {
          if (!await _chat.saveExploration(target.attemptRef, work)) {
            return null;
          }
          progress(work);
          // Batches are independent (append-only notes), so a few run in
          // parallel; checkpoints still commit in cursor order.
          while (!work.complete) {
            if (budget.remaining < chatAnswerReserveTime) {
              work = checkpoint(
                cursor: work.cursor,
                notes: work.notes,
                stopReason: 'deadline',
              );
              break;
            }
            final previousNotes = jsonEncode(work.promptData['notes']);
            final batchBytes = [
              chatGlobalBatchBytes,
              budget.inputBytesFor(chatNotesMaxTokens) -
                  utf8.encode(previousNotes).length -
                  utf8.encode(notesSystem).length -
                  4000,
            ].reduce((a, b) => a < b ? a : b);
            if (answerNow?.call() ?? false) {
              work = checkpoint(
                cursor: work.cursor,
                notes: work.notes,
                stopReason: 'user',
              );
              break;
            }
            final group = <({List<ChatSource> batch, String user})>[];
            var cursor = work.cursor;
            String? stop;
            while (group.length < chatGlobalConcurrency &&
                cursor < windows.length) {
              final batch = <ChatSource>[];
              var bytes = 0;
              for (final window in windows.skip(cursor)) {
                final size = utf8.encode(jsonEncode(_source(window))).length;
                // Batch berhenti di batas bab begitu cukup penuh: satu label
                // per batch dan catatan rapi per bab.
                if (batch.isNotEmpty &&
                    (bytes + size > batchBytes ||
                        batch.length == chatGlobalBatchWindows ||
                        bytes * 10 >= batchBytes * 6 &&
                            window.anchors.first.chapterId !=
                                batch.last.anchors.first.chapterId)) {
                  break;
                }
                batch.add(window);
                bytes += size;
              }
              final user = chatRetrievalUser(
                {
                  if (plan.strategy != ChatSearchStrategy.global)
                    'question': target.question,
                  'book': input.book.title,
                  'examinedBefore': cursor,
                  'totalWindows': work.total,
                  'previousNotes': work.promptData['notes'],
                  'sources': [for (final w in batch) _source(w)],
                  'newWindowIds': batch.map((w) => w.id).toList(),
                },
                notesSystem,
                chatPromptBytes + chatGlobalBatchBytes,
              );
              if (batch.isEmpty ||
                  !budget.fits(
                    utf8.encode(user).length + utf8.encode(notesSystem).length,
                    chatNotesMaxTokens + chatAnswerReserveTokens,
                  )) {
                stop = 'budget';
                break;
              }
              group.add((batch: batch, user: user));
              cursor += batch.length;
            }
            if (group.isEmpty) {
              work = checkpoint(
                cursor: work.cursor,
                notes: work.notes,
                stopReason: stop ?? 'budget',
              );
              break;
            }
            for (final g in group) {
              if (!await _chat.validateRetrieval(target.attemptRef, g.batch)) {
                return null;
              }
            }
            _check(cancel);
            progress(work, label: labelOf(group.first.batch));
            onStep?.call(
              ChatStep.read(
                labelOf(group.first.batch) ?? 'bab berikutnya',
                status: ChatStepStatus.running,
              ),
            );
            final raws = await Future.wait([
              for (final g in group)
                _complete(
                  key,
                  target.model,
                  notesSystem,
                  g.user,
                  chatNotesMaxTokens,
                  cancel,
                  budget,
                  guard,
                ),
            ]);
            for (final (i, g) in group.indexed) {
              final allowed = g.batch.map((w) => w.id).toSet();
              List<ChatExplorationNote> fresh;
              try {
                fresh = parseChatGlobalNotes(
                  raws[i],
                  allowed: allowed,
                  batch: true,
                );
              } on FormatException catch (e) {
                // Catatan kepanjangan/terpotong/ID asing: ulang sekali per
                // batch dalam ledger yang sama; ini langkah baca, bukan jatah
                // perbaikan jawaban.
                if (budget.batchRetries >= chatMaxBatchRetries) rethrow;
                budget.batchRetries++;
                onStep?.call(ChatStep.retry(labelOf(g.batch) ?? 'bab'));
                _check(cancel);
                fresh = parseChatGlobalNotes(
                  await _complete(
                    key,
                    target.model,
                    notesSystem,
                    chatRetrievalUser(
                      {
                        ...jsonDecode(g.user) as Map<String, Object?>,
                        'repair':
                            'Output sebelumnya ditolak: ${e.message}. Tulis jauh lebih ringkas: maksimal 5 catatan pendek, total di bawah 900 karakter, hanya ID dari sources batch ini, JSON lengkap.',
                      },
                      notesSystem,
                      chatPromptBytes + chatGlobalBatchBytes,
                    ),
                    chatNotesMaxTokens,
                    cancel,
                    budget,
                    guard,
                    history: [
                      {'role': 'assistant', 'content': raws[i]},
                      {
                        'role': 'user',
                        'content':
                            'Output di atas ditolak: ${e.message}. Ulangi untuk batch yang sama, jauh lebih ringkas (maksimal 5 catatan pendek, total di bawah 900 karakter), JSON lengkap, hanya source_ids dari sources.',
                      },
                    ],
                  ),
                  allowed: allowed,
                  batch: true,
                );
              }
              final next = checkpoint(
                cursor: work.cursor + g.batch.length,
                notes: [...work.notes, ...fresh],
              );
              next.validate(target, windows);
              _check(cancel);
              if (!await _chat.saveExploration(
                target.attemptRef,
                next,
                evidence: g.batch,
              )) {
                return null;
              }
              work = next;
              onStep?.call(
                ChatStep.read(
                  labelOf(g.batch) ?? 'bab',
                  detail: '${fresh.length} catatan',
                ),
              );
              // Bab yang baru selesai dibaca masuk cache (seluruh buku saja).
              if (plan.strategy == ChatSearchStrategy.global) {
                for (final entry in chapterLastIndex.entries) {
                  if (entry.value < work.cursor && cachedIds.add(entry.key)) {
                    await _notes.save(
                      current,
                      chapterId: entry.key,
                      manifest: chapterManifests[entry.key]!,
                      model: target.model,
                      notes: chatCachedNotesFor(
                        entry.key,
                        work.notes,
                        windowsById,
                      ),
                    );
                    _check(cancel);
                  }
                }
              }
              progress(
                work,
                label: i + 1 < group.length
                    ? labelOf(group[i + 1].batch)
                    : labelOf(g.batch),
              );
            }
          }
          // Alasan berhenti ikut tersimpan supaya Lanjutkan/UI membacanya.
          if (!work.complete &&
              work.stopReason != null &&
              !await _chat.saveExploration(target.attemptRef, work)) {
            return null;
          }
          if (!work.complete && work.stopReason != null) {
            onStep?.call(
              ChatStep.stop(
                chatStopLabel(work.stopReason!),
                detail: '${work.cursor}/${work.total} potongan',
              ),
            );
          }
          exploration = work;
          // Most-cited windows first; whatever does not fit stays uncited
          // in the notes rather than failing the answer.
          final citations = <String, int>{};
          for (final n in work.notes) {
            for (final id in n.sourceIds) {
              citations[id] = (citations[id] ?? 0) + 1;
            }
          }
          final cited = [
            for (final w in windows)
              if (citations.containsKey(w.id)) w,
          ]..sort((a, b) => citations[b.id]!.compareTo(citations[a.id]!));
          final packed = chatSplitLargeSources(
            chatPackGlobalSources([...globalQuotes, ...cited]),
            sourceBudget ~/ 3,
          );
          selected = fitChatSources([
            ...packed.where((s) => globalQuotes.any((q) => _overlaps(q, s))),
            ...packed.where((s) => !globalQuotes.any((q) => _overlaps(q, s))),
          ], maxBytes: sourceBudget);
          noteSourceIds = {
            for (final w in cited)
              if (selected.where((s) => _contains(s, w)).firstOrNull
                  case final s?)
                w.id: s.id,
          };
        }
      } else if (!plan.needsClarification &&
          !plan.strategy.reads &&
          plan.strategy != ChatSearchStrategy.offTopic &&
          input.chunks.isNotEmpty) {
        final searched = <String>{...?saved?.searchedQueries};
        // Bab yang boleh jadi kandidat; tersimpan di checkpoint untuk Lanjutkan.
        final allowedChapters = plan.chapterIds.isEmpty
            ? content
            : plan.chapterIds;
        if (saved != null) {
          selected = _uniqueSources([
            ...input.quoted,
            for (final s in input.chunks)
              if (saved.selectedIds.contains(s.id)) s,
          ]);
        }
        var searchedThisTurn = 0;
        var queries =
            saved?.pendingQueries ??
            (plan.queries.isEmpty ? [plan.englishQuery] : plan.queries);
        var candidates = <ChatSource>[];
        ChatExploration searchCheckpoint(
          List<String> pending, {
          String? stopReason,
        }) => ChatExploration(
          book: current,
          sessionId: target.sessionId,
          turnId: target.id,
          question: target.question,
          model: target.model,
          manifest: chatWindowManifest(input.chunks),
          query: plan.englishQuery,
          cursor: 0,
          total: input.chunks.length,
          notes: [],
          strategy: plan.strategy,
          chapterIds: allowedChapters,
          searchedQueries: searched.toList(),
          pendingQueries: pending,
          selectedIds: selected.map((s) => s.id).toList(),
          stopReason: stopReason,
        );
        var searchWork = searchCheckpoint(queries);
        if (!await _chat.saveExploration(
          target.attemptRef,
          searchWork,
          evidence: selected,
        )) {
          return null;
        }
        // Rounds continue while the selector asks for more and the shared
        // ledger still leaves room for the answer; identical rounds stop.
        var previousSelection = '';
        for (var round = 0; searchedThisTurn < 9; round++) {
          if (round > 0 && budget.remaining < chatAnswerReserveTime) {
            searchWork = searchCheckpoint(queries, stopReason: 'deadline');
            break;
          }
          final capacity = 64 - searched.length;
          final fresh = queries
              .where((q) => !searched.contains(q))
              .take(capacity < 3 ? capacity : 3)
              .toList();
          if (fresh.isEmpty) break;
          onStep?.call(
            ChatStep.search(fresh.join(' · '), status: ChatStepStatus.running),
          );
          final rankings = await _rank(
            input.chunks,
            current,
            input.book.parserVersion,
            original,
            fresh,
            input.quoted,
            key,
            cancel,
            target,
            onIndexProgress,
            budget,
          );
          // Front/back matter (Endnotes, Imprint) keluar dari kandidat kalau
          // planner membatasi bab isi; index embedding tetap seluruh buku.
          final allowed = allowedChapters.toSet();
          final found = [
            for (final s in chatFuseRanks(rankings, quoteSources: input.quoted))
              if (allowed.contains(s.anchors.first.chapterId) ||
                  input.quoted.contains(s))
                s,
          ];
          candidates = _uniqueSources([
            ...input.quoted,
            ...selected,
            ...found,
            ...candidates,
          ]).take(chatMaxCandidates).toList();
          validateChatSources(candidates, current, input.paragraphs);
          final forced = input.quoted.map((s) => s.id).toSet();
          final selectorUser = chatRetrievalUser(
            {
              'question': target.question,
              'history': history,
              'searchedQueries': searched.toList(),
              if (input.quoted.length == 1)
                'selectedSourceId': candidates.indexOf(input.quoted.single) + 1,
              'selectedSourceIds': [
                for (final (i, source) in candidates.indexed)
                  if (forced.contains(source.id)) i + 1,
              ],
              'candidates': [
                for (final (i, source) in candidates.indexed)
                  {
                    'id': i + 1,
                    'chapter': source.chapterTitle,
                    'paragraphStart': source.anchors.first.paragraphIndex,
                    'paragraphEnd': source.anchors.last.paragraphIndex,
                    'text': source.text,
                  },
              ],
            },
            chatSelectionSystem,
            chatSelectorBytes,
          );
          if (!budget.fits(
            utf8.encode(selectorUser).length,
            600 + chatAnswerReserveTokens,
          )) {
            searchWork = searchCheckpoint(queries, stopReason: 'budget');
            break;
          }
          if (!await _chat.validateRetrieval(target.attemptRef, candidates)) {
            return null;
          }
          final raw = await _complete(
            key,
            target.model,
            chatSelectionSystem,
            selectorUser,
            600,
            cancel,
            budget,
            guard,
          );
          // Putaran lanjutan menambah bukti; pilihan putaran sebelumnya tidak
          // hilang hanya karena query baru tidak menemukan apa pun.
          selected = fitChatSources(
            _uniqueSources([
              ...parseChatSelection(raw, candidates, input.quoted),
              ...selected,
            ]),
            maxBytes: sourceBudget,
          );
          searched.addAll(fresh);
          searchedThisTurn += fresh.length;
          onStep?.call(
            ChatStep.search(
              fresh.join(' · '),
              detail: '${selected.length} sumber',
            ),
          );
          queries = chatMissingQueries(raw)
              .where((q) => !searched.contains(q))
              .take(2)
              .toList();
          if (searched.length >= 64) queries = [];
          final selection = selected.map((s) => s.id).join(',');
          final stagnant = queries.isNotEmpty && selection == previousSelection;
          previousSelection = selection;
          searchWork = searchCheckpoint(
            queries,
            stopReason: stagnant ? 'stagnant' : null,
          );
          if (!await _chat.saveExploration(
            target.attemptRef,
            searchWork,
            evidence: selected,
          )) {
            return null;
          }
          if (queries.isEmpty || stagnant) break;
        }
        if (searchWork.stopReason != null) {
          onStep?.call(
            ChatStep.stop(
              chatStopLabel(searchWork.stopReason!),
              detail: '${searched.length} query',
            ),
          );
        }
        exploration = searchWork;
        // Add adjacent windows after the direct evidence, without losing forced quotes.
        final neighbors = <ChatSource>[];
        for (final source in selected) {
          final i = input.chunks.indexOf(source);
          for (final j in [i - 1, i + 1]) {
            if (i >= 0 &&
                j >= 0 &&
                j < input.chunks.length &&
                input.chunks[j].anchors.first.chapterId ==
                    source.anchors.first.chapterId) {
              neighbors.add(input.chunks[j]);
            }
          }
        }
        selected = fitChatSources(
          _uniqueSources([...selected, ...neighbors]),
          maxBytes: sourceBudget,
        );
      }
      _check(cancel);
      final sourceIds = {
        for (final (i, source) in selected.indexed) source.id: 'S${i + 1}',
      };
      selected = [
        for (final (i, source) in selected.indexed)
          ChatSource(
            id: 'S${i + 1}',
            chapterTitle: source.chapterTitle,
            anchors: source.anchors,
          ),
      ];
      final work = exploration;
      final labels = [
        for (final id in work?.chapterIds ?? const <int>[])
          if (tocById[id] case final c?) chatChapterLabel(c),
      ];
      final prompt = buildChatPrompt(
        session: input.session,
        current: current,
        question: input.turn.question,
        beforeSequence: input.turn.sequence,
        history: input.history,
        sources: selected,
        paragraphs: input.paragraphs,
        title: input.book.title,
        author: input.book.author,
        quote: quote,
        maxBytes: answerInput,
        exploration: work == null && plan.clarification == null
            ? null
            : {
                if (plan.needsClarification && plan.clarification != null)
                  'clarification': plan.clarification,
                if (work != null) ...{
                  'scope': switch (work.strategy) {
                    ChatSearchStrategy.chapters => 'chapters',
                    ChatSearchStrategy.global => 'book',
                    _ => 'search',
                  },
                  'complete': work.complete,
                  if (work.stopReason != null) 'stopReason': work.stopReason,
                  if (work.strategy.reads) ...{
                    'examinedChapters': labels.take(60).toList(),
                    'chapterCount': labels.length,
                    if (cachedChapterCount > 0)
                      'notesFromCache': cachedChapterCount,
                    'examinedWindows': work.cursor,
                    'totalWindows': work.total,
                  } else ...{
                    'searchedQueries': work.searchedQueries,
                    'pendingQueries': work.pendingQueries,
                    'wholeBookExamined': false,
                  },
                  'notesAreGenerated': true,
                  'notes': [
                    for (final n in work.notes)
                      {
                        'text': n.text,
                        'source_ids': {
                          for (final id in n.sourceIds)
                            ?sourceIds[noteSourceIds[id] ?? id],
                        }.toList(),
                      },
                  ],
                },
              },
      );
      // Repository rechecks live revision/hash/owner and freezes the exact set.
      if (!await _chat.prepareSources(input.turn.attemptRef, prompt.sources)) {
        return null;
      }
      _check(cancel);
      return PreparedChat._(
        _router,
        key,
        input.turn.model,
        prompt,
        current,
        input.paragraphs,
        exploration,
        budget,
        () => !_disposed
            ? _chat.validatePrepared(input.turn.attemptRef, prompt.sources)
            : Future.value(false),
      );
    } on FormatException catch (e) {
      throw AiException(AiError.invalidResponse, detail: e.message);
    }
  }

  Future<String> _complete(
    String key,
    String model,
    String system,
    String user,
    int tokens,
    CancelToken? cancel,
    ChatBudget budget,
    Future<bool> Function() guard, {
    List<Map<String, String>> history = const [],
  }) async {
    _check(cancel);
    if (!await guard()) throw StateError('Attempt penelusuran sudah berhenti');
    _check(cancel);
    final reservation = budget.reserveCompletion(
      system,
      [user, ...history.map((m) => m['content']!)].join(),
      tokens,
    );
    var result = '';
    var bytes = 0;
    await for (final delta in _router.chatStream(
      apiKey: key,
      model: model,
      system: system,
      user: user,
      history: history,
      maxTokens: tokens,
      inputBytes: chatRequestInputBytes,
      onUsage: (usage) => budget.settle(reservation, usage),
      cancel: cancel,
    )) {
      _check(cancel);
      bytes += utf8.encode(delta).length;
      if (bytes > chatPromptBytes) {
        throw const FormatException('Retrieval output budget');
      }
      result += delta;
    }
    return result;
  }

  void _embeddingBudget(List<String> input) {
    if (input.any((s) => s.isEmpty || utf8.encode(s).length > 8000) ||
        input.fold<int>(0, (n, s) => n + utf8.encode(s).length) >
            chatEmbeddingInputBytes) {
      throw const FormatException('Buku/query melebihi budget embedding');
    }
  }

  Future<List<List<ChatSource>>> _rank(
    List<ChatSource> chunks,
    ChatBookRef book,
    int parserVersion,
    String original,
    List<String> english,
    List<ChatSource> quoted,
    String key,
    CancelToken? cancel,
    ChatTurn target,
    void Function(int, int)? onProgress,
    ChatBudget budget,
  ) async {
    final previous = _indexTail;
    final done = Completer<void>();
    _indexTail = done.future;
    await previous;
    try {
      _check(cancel);
      return await _rankIndex(
        chunks,
        book,
        parserVersion,
        original,
        english,
        quoted,
        key,
        cancel,
        target,
        onProgress,
        budget,
      );
    } finally {
      done.complete();
    }
  }

  Future<List<List<ChatSource>>> _rankIndex(
    List<ChatSource> chunks,
    ChatBookRef book,
    int parserVersion,
    String original,
    List<String> english,
    List<ChatSource> quoted,
    String key,
    CancelToken? cancel,
    ChatTurn target,
    void Function(int, int)? onProgress,
    ChatBudget budget,
  ) async {
    Future<void> guard() async {
      _check(cancel);
      final b = await (_db.select(
        _db.books,
      )..where((b) => b.id.equals(book.bookId))).getSingleOrNull();
      final t = await (_db.select(
        _db.chatTurns,
      )..where((t) => t.id.equals(target.id))).getSingleOrNull();
      final session = await (_db.select(
        _db.chatSessions,
      )..where((s) => s.id.equals(target.sessionId))).getSingleOrNull();
      _check(cancel);
      if (session == null ||
          session.bookId != book.bookId ||
          session.contentRevision != book.contentRevision ||
          b == null ||
          b.contentRevision != book.contentRevision ||
          b.parserVersion != parserVersion ||
          t == null ||
          t.sessionId != target.sessionId ||
          t.attempt != target.attempt ||
          !ChatPhase.values.any((p) => p.name == t.phase && p.isRunning)) {
        throw StateError('Index attempt sudah tidak aktif');
      }
    }

    final store = ChatIndexRepository(_db);
    final manifest = chatTextHash(
      jsonEncode([
        for (final s in chunks)
          {
            'id': s.id,
            'chapter': s.chapterTitle,
            'anchors': [
              for (final a in s.anchors)
                [
                  a.chapterId,
                  a.paragraphIndex,
                  a.start,
                  a.end,
                  a.paragraphHash,
                ],
            ],
          },
      ]),
    );
    Future<List<List<ChatSource>>> run(ChatEmbeddingModel embedding) async {
      final ChatIndexKey indexKey = (
        book: book,
        parserVersion: parserVersion,
        chunkPolicyVersion: chatChunkPolicyVersion,
        embedding: embedding,
        queryTemplateVersion: chatQueryTemplateVersion,
      );
      final queries = [
        embedding == ChatEmbeddingModel.qwen8b
            ? original
            : original.substring(chatQueryPrefix.length),
        for (final query in english)
          '${embedding == ChatEmbeddingModel.qwen8b ? chatQueryPrefix : ''}$query',
      ];
      final documents = chunks.map((s) => s.text).toList();
      _embeddingBudget([...documents, ...queries]);
      if (_indexKey != indexKey ||
          _manifest != manifest ||
          _documents == null) {
        // Drop the previous book from RAM before loading/building this index.
        _documents = null;
        final cached = await store.load(
          indexKey,
          manifest,
          documents.length,
          guard,
        );
        final vectors = cached.vectors;
        onProgress?.call(vectors.length, documents.length);
        // Sampai tiga batch dokumen dikirim bersamaan; disimpan urut ordinal
        // supaya prefix index tetap valid saat cancel/gagal di tengah.
        while (vectors.length < documents.length) {
          await guard();
          final inputs = <List<String>>[];
          var offset = vectors.length;
          while (inputs.length < chatGlobalConcurrency &&
              offset < documents.length) {
            final input = documents.skip(offset).take(64).toList();
            budget.reserveEmbedding(input);
            inputs.add(input);
            offset += input.length;
          }
          final batches = await Future.wait([
            for (final input in inputs)
              _router.embeddings(
                apiKey: key,
                model: embedding,
                input: input,
                cancel: cancel,
              ),
          ]);
          for (final batch in batches) {
            await store.saveBatch(
              cached.id,
              vectors.length,
              batch,
              embedding.dimensions,
              guard,
            );
            vectors.addAll(batch);
            onProgress?.call(vectors.length, documents.length);
          }
        }
        await guard();
        _indexKey = indexKey;
        _manifest = manifest;
        _documents = vectors;
      }
      final vectors = _documents!;
      await guard();
      budget.reserveEmbedding(queries);
      final q = await _router.embeddings(
        apiKey: key,
        model: embedding,
        input: queries,
        cancel: cancel,
      );
      _check(cancel);
      final quoteIds = quoted.map((s) => s.id).toSet();
      return [
        chatDenseSearch(chunks, vectors, q[0], quoteIds: quoteIds),
        for (var i = 0; i < english.length; i++) ...[
          chatDenseSearch(chunks, vectors, q[i + 1], quoteIds: quoteIds),
          ChatLexicalIndex(chunks)
              .search(english[i], quoteIds: quoteIds, k: chatMaxCandidates),
        ],
      ];
    }

    try {
      return await run(ChatEmbeddingModel.qwen8b);
    } on AiException catch (e) {
      final status = e.status;
      final providerFailure =
          e.error == AiError.timeout ||
          e.error == AiError.network ||
          e.error == AiError.http &&
              status != null &&
              ([404, 408, 429].contains(status) ||
                  status >= 500 && status <= 599);
      if (!providerFailure) rethrow;
      _check(cancel);
      return run(ChatEmbeddingModel.openaiLarge);
    }
  }
}

Map<String, Object?> _source(ChatSource s) => {
  'id': s.id,
  'chapter': s.chapterTitle,
  'paragraphStart': s.anchors.first.paragraphIndex,
  'paragraphEnd': s.anchors.last.paragraphIndex,
  'text': s.text,
};

String _rangeKey(ChatSource s) => jsonEncode([
  for (final a in s.anchors)
    [a.chapterId, a.paragraphIndex, a.start, a.end, a.paragraphHash],
]);

String _anchorKey(SourceAnchor a) =>
    '${a.chapterId}:${a.paragraphIndex}:${a.start}:${a.end}';

/// [outer] memuat seluruh range [inner] (window asli yang dikutip catatan).
bool _contains(ChatSource outer, ChatSource inner) => inner.anchors.every(
  (a) => outer.anchors.any(
    (o) =>
        o.chapterId == a.chapterId &&
        o.paragraphIndex == a.paragraphIndex &&
        o.start <= a.start &&
        o.end >= a.end,
  ),
);

bool _overlaps(ChatSource a, ChatSource b) {
  final keys = a.anchors.map(_anchorKey).toSet();
  return b.anchors.any((x) => keys.contains(_anchorKey(x))) || _contains(b, a);
}

List<ChatSource> _uniqueSources(List<ChatSource> sources) {
  final ranges = <String>{};
  return [
    for (final s in sources)
      if (ranges.add(_rangeKey(s))) s,
  ];
}

/// Raw draft is durable transport data; preview is provisional, answer is final.
/// [repair] > 0 berarti output sebelumnya invalid dan jawaban dikirim ulang;
/// [repairReason] menjelaskan kegagalan yang sedang diperbaiki.
class ChatStreamFrame {
  const ChatStreamFrame(
    this.draft, {
    this.answer,
    this.preview = const [],
    this.repair = 0,
    this.repairReason,
  });
  final String draft;
  final ChatAnswer? answer;
  final List<ChatAnswerBlock> preview;
  final int repair;
  final String? repairReason;
}

class PreparedChat {
  PreparedChat._(
    this._router,
    this._key,
    this.model,
    this.prompt,
    this.book,
    this._paragraphs,
    this._exploration,
    this._budget,
    this._validate,
  );
  final OpenRouterService _router;
  final String _key, model;
  final ChatPrompt prompt;
  final ChatBookRef book;
  final Map<ChatParagraphRef, ChatParagraph> _paragraphs;
  final Future<bool> Function() _validate;
  final ChatExploration? _exploration;
  final ChatBudget _budget;
  bool _started = false;

  Stream<ChatStreamFrame> stream({
    CancelToken? cancel,
    void Function(ChatStep step)? onStep,
  }) async* {
    if (_started) throw StateError('Request chat sudah dipakai');
    _started = true;
    if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
    try {
      if (!await _validate()) return;
      if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
      var history = const <Map<String, String>>[];
      String? reason;
      // Draft durable hanya boleh bertambah (checkpoint memeriksa prefix):
      // output attempt sebelumnya tetap di depan, perbaikan ditambahkan.
      var prefix = '';
      for (var attempt = 0; ; attempt++) {
        onStep?.call(ChatStep.answer(status: ChatStepStatus.running));
        final decoder = ChatAnswerDecoder(
          prompt: prompt,
          current: book,
          paragraphs: _paragraphs,
        );
        final reservation = _budget.reserveCompletion(
          prompt.system,
          [prompt.user, ...history.map((m) => m['content']!)].join(),
          chatAnswerMaxTokens,
        );
        var validatedParts = 0;
        await for (final delta in _router.chatStream(
          apiKey: _key,
          model: model,
          system: prompt.system,
          user: prompt.user,
          history: history,
          inputBytes: chatRequestInputBytes,
          onUsage: (usage) => _budget.settle(reservation, usage),
          cancel: cancel,
        )) {
          decoder.add(delta);
          final preview = decoder.preview.blocks;
          final citedParts = preview.where((b) => b.sources.isNotEmpty).length;
          if (citedParts > validatedParts) {
            if (!await _validate()) return;
            if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
          }
          validatedParts = citedParts;
          yield ChatStreamFrame(
            '$prefix${decoder.raw}',
            preview: preview,
            repair: attempt,
            repairReason: reason,
          );
        }
        if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
        if (!await _validate()) return;
        if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
        ChatAnswer answer;
        try {
          answer = decoder.finish();
        } on FormatException catch (e) {
          // Format/sumber invalid: perbaiki maksimal dua kali dalam ledger
          // yang sama. HTTP/saldo/kunci tidak pernah diulang otomatis.
          if (attempt >= chatMaxRepairs || _budget.expired) rethrow;
          _budget.repairs++;
          onStep?.call(ChatStep.repair(attempt + 1, chatMaxRepairs));
          reason = e.message;
          history = [
            {'role': 'assistant', 'content': decoder.raw},
            {
              'role': 'user',
              'content': jsonEncode({
                'repair': reason,
                'instruction': 'Output sebelumnya ditolak aplikasi karena alasan di repair. Kirim ulang SELURUH jawaban sebagai satu JSON valid sesuai skema sistem, dengan isi yang sama, perbaiki hanya masalah itu. Semua source_ids harus dari sources.',
              }),
            },
          ];
          prefix = '$prefix${decoder.raw}\n';
          yield ChatStreamFrame(
            prefix,
            preview: decoder.preview.blocks,
            repair: attempt + 1,
            repairReason: reason,
          );
          continue;
        }
        final work = _exploration;
        if (work != null && !work.complete) {
          if (answer.blocks.length >= 32) {
            throw const FormatException(
              'Jawaban terlalu panjang untuk catatan cakupan',
            );
          }
          answer = ChatAnswer(
            status: ChatAnswerStatus.partial,
            formatVersion: 2,
            blocks: [
              ...answer.blocks,
              ChatAnswerBlock(
                text: work.strategy.reads
                    ? 'Udah diperiksa ${work.cursor}/${work.total} potongan${work.strategy == ChatSearchStrategy.chapters ? ' dari bab yang diminta' : ' isi buku'}. Masih ada ${work.total - work.cursor} potongan yang belum diperiksa. Pakai Lanjutkan buat meneruskan penelusuran.'
                    : 'Masih ada ${work.pendingQueries.length} kebutuhan pencarian yang belum diperiksa. Pakai Lanjutkan buat meneruskan penelusuran.',
                kind: ChatAnswerKind.conversation,
                sources: [],
              ),
            ],
          );
        }
        onStep?.call(ChatStep.answer());
        yield ChatStreamFrame(
          '$prefix${decoder.raw}',
          answer: answer,
          repair: attempt,
        );
        return;
      }
    } on FormatException catch (e) {
      throw AiException(AiError.invalidResponse, detail: e.message);
    }
  }
}

final chatContextRepositoryProvider = Provider<ChatContextRepository>((ref) {
  final repo = ChatContextRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(chatRepositoryProvider),
    ref.watch(openRouterServiceProvider),
    ref.watch(apiKeyStoreProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});
