import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/chat_context_repository.dart';
import 'package:luma/data/repositories/chat_repository.dart';
import 'package:luma/data/services/api_key_store.dart';
import 'package:luma/data/services/openrouter_service.dart';
import 'package:luma/domain/chat_exploration.dart';
import 'package:luma/domain/chat_prompt.dart';
import 'package:luma/domain/models/book.dart';
import 'package:luma/domain/models/book_chat.dart';

import '../support/book_chat_discussion.dart';

class _Keys extends ApiKeyStore {
  _Keys(this.key);
  final String key;
  @override
  Future<String?> read() async => key;
}

/// Live proof uses the production pipeline, with the existing paid-run ledger.
/// Embeddings are blocked here: this diagnostic measures global scan + resume.
class _Measured implements HttpClientAdapter {
  _Measured(this.inner, this.budget, this.model, this.contextLength, this.save);
  final HttpClientAdapter inner;
  final DiscussionBudget budget;
  final String model;
  final int contextLength;
  final void Function() save;
  final rows = <Map<String, Object?>>[];
  final dispatched = <String>{};
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path != '/chat/completions' || rows.length >= 10) {
      throw StateError(
        'Diagnostic only permits ten global completions, no embeddings',
      );
    }
    final body = options.data as Map;
    final identity = jsonEncode(body);
    if (!dispatched.add(identity)) {
      throw StateError('No repeated dispatch in diagnostic');
    }
    final guarded = DiscussionAdapter(
      inner,
      budget,
      model: model,
      contextLength: contextLength,
    );
    final row = <String, Object?>{
      'system': (body['messages'] as List).first['content'],
      'user': (body['messages'] as List).last['content'],
      'maxTokens': body['max_tokens'],
      'state': 'dispatch_pending',
    };
    rows.add(row);
    save();
    final watch = Stopwatch()..start();
    try {
      final response = await guarded.fetch(
        options,
        requestStream,
        cancelFuture,
      );
      row['reservation'] = guarded.reservation;
      row['httpStatus'] = response.statusCode;
      return ResponseBody(
        _observe(response.stream, row, guarded.reservation!, watch),
        response.statusCode,
        headers: response.headers,
      );
    } catch (e) {
      row['errorType'] = e.runtimeType.toString();
      row['reservation'] = guarded.reservation;
      save();
      rethrow;
    }
  }

  Stream<Uint8List> _observe(
    Stream<Uint8List> stream,
    Map<String, Object?> row,
    int reservation,
    Stopwatch watch,
  ) async* {
    final bytes = <int>[];
    try {
      await for (final chunk in stream) {
        bytes.addAll(chunk);
        if (bytes.length > 1000000) throw StateError('Response budget');
        yield chunk;
      }
    } finally {
      Map<String, dynamic>? usage;
      var answer = '';
      for (final line in utf8.decode(bytes, allowMalformed: true).split('\n')) {
        if (!line.startsWith('data: ') ||
            line.substring(6).trim() == '[DONE]') {
          continue;
        }
        try {
          final event = jsonDecode(line.substring(6)) as Map;
          if (event['usage'] is Map) {
            usage = Map<String, dynamic>.from(event['usage'] as Map);
          }
          final choices = event['choices'];
          if (choices is List && choices.isNotEmpty) {
            final content = choices.first['delta']?['content'];
            if (content is String) answer += content;
          }
        } on FormatException {
          /* Incomplete transport remains unknown usage. */
        }
      }
      budget.settle(reservation, usage);
      row.addAll({
        'state': 'response_received',
        'usage': usage,
        'raw': answer,
        'totalMs': watch.elapsedMilliseconds,
      });
      save();
    }
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}

void main() {
  test(
    'production global scan and explicit continuation (paid opt-in)',
    () async {
      final env = Platform.environment;
      final key = env['OPENROUTER_API_KEY'];
      if (key == null || key.isEmpty) throw StateError('Local key required');
      final model = env['OPENROUTER_MODEL'] ?? 'z-ai/glm-5.3-flash';
      final report = File(
        '/tmp/luma-adaptive-${DateTime.now().microsecondsSinceEpoch}.json',
      );
      final lock = File('/tmp/luma-discussion-budget.lock')
          .openSync(mode: FileMode.append);
      lock.lockSync(FileLock.exclusive);
      final budget = DiscussionBudget(File('/tmp/luma-discussion-budget.json'));
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://openrouter.ai/api/v1',
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      final db = AppDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      final repo = ChatRepository(db);
      ChatContextRepository? context;
      final results = <Map<String, Object?>>[];
      final result = <String, Object?>{
        'issue': 138,
        'streamingIssue': 141,
        'model': model,
        'scope': 'production global pipeline on original synthetic 4-chapter book; no retrieval or embedding billing measured',
        'turns': results,
        'status': 'started',
        'budgetLedger': budget.file.path,
      };
      _Measured? measured;
      void save() => report.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          ...result,
          'requests': measured?.rows ?? [],
          'heldUsd': budget.heldUsd,
        }),
        flush: true,
      );
      try {
        final metadata = await dio.get<Map<String, dynamic>>('/models');
        final info = (metadata.data!['data'] as List).singleWhere(
          (m) => m['id'] == model,
        ) as Map;
        result['modelMetadata'] = info;
        final reasoning = discussionReasoning(info);
        result['reasoning'] = reasoning;
        measured = _Measured(
          dio.httpClientAdapter,
          budget,
          model,
          info['context_length'] as int,
          save,
        );
        dio.httpClientAdapter = measured;
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              final body = Map<String, dynamic>.from(options.data as Map);
              body['provider'] = discussionProvider;
              body['reasoning'] = reasoning;
              body['stream_options'] = {'include_usage': true};
              options.data = body;
              handler.next(options);
            },
          ),
        );
        await db
            .into(db.settings)
            .insert(SettingsCompanion.insert(key: 'ai.model', value: model));
        final bookId = await db
            .into(db.books)
            .insert(
              BooksCompanion.insert(
                sourceType: SourceType.epub,
                title: 'The Shared Rain Ledger',
                parserVersion: 1,
                totalChars: 6000,
              ),
            );
        const topics = [
          'Mira proposes a shared rain tank. She argues each household should receive an equal daily allowance. The council approves a trial, not a permanent rule.',
          'During the trial, the clinic needs more water than a household. Mira records this exception and revises the proposal to prioritize essential needs.',
          'The north district repairs the pipes while the south supplies spare barrels. They disagree about credit, then publish a common ledger recording both contributions.',
          'The council adopts need-based emergency allocation and equal ordinary allowances. Mira says the ledger should stay open to corrections; the final vote includes a review after the next dry season.',
        ];
        for (var c = 0; c < topics.length; c++) {
          final chapter = await db
              .into(db.chapters)
              .insert(
                ChaptersCompanion.insert(
                  bookId: bookId,
                  sortOrder: c,
                  title: 'Chapter ${c + 1}',
                  charOffset: c * 1500,
                ),
              );
          for (var p = 0; p < 8; p++) {
            await db
                .into(db.paragraphs)
                .insert(
                  ParagraphsCompanion.insert(
                    chapterId: chapter,
                    paragraphIndex: p,
                    type: ParagraphType.paragraph,
                    content: 'Ledger entry ${c + 1}.${p + 1}: ${topics[c]}',
                    groupIndex: Value(p),
                  ),
                );
          }
        }
        context = ChatContextRepository(
          db,
          repo,
          OpenRouterService(dio),
          _Keys(key),
        );
        var turn = await repo.createFirstTurn(
          (bookId: bookId, contentRevision: 1),
          question: 'Telusuri keseluruhan buku ini, semua bab dari awal sampai akhir. Jelaskan perkembangan gagasan Mira dan hubungan antar bab, terutama perubahan aturan pembagian air.',
          model: model,
          promptVersion: chatPromptVersion,
        );
        for (var step = 0; step < 2; step++) {
          final time = Stopwatch()..start();
          final prepared = await context.prepare(turn);
          if (prepared == null) throw StateError('Preparation rejected');
          int? firstReadableMs, firstCitationMs;
          var previewFrames = 0;
          ChatStreamFrame? last;
          await for (final update in prepared.stream()) {
            last = update;
            if (update.answer == null &&
                update.preview.any((b) => b.text.isNotEmpty)) {
              firstReadableMs ??= time.elapsedMilliseconds;
              previewFrames++;
            }
            if (update.answer == null &&
                update.preview.any((b) => b.sources.isNotEmpty)) {
              firstCitationMs ??= time.elapsedMilliseconds;
            }
          }
          final frame = last!;
          expect(firstReadableMs, isNotNull);
          expect(firstReadableMs!, lessThanOrEqualTo(time.elapsedMilliseconds));
          expect(firstCitationMs, isNotNull);
          if (frame.answer == null) throw StateError('No validated answer');
          await repo.finalize(
            turn.attemptRef,
            phase: ChatPhase.done,
            draft: frame.draft,
            answer: frame.answer,
          );
          final latest =
              (await repo.watchTurns(bookId, turn.sessionId).first).last;
          final work = ChatExploration.parse(latest.exploration!);
          expect(work.strategy, ChatSearchStrategy.global);
          results.add({
            'sequence': step,
            'cursor': work.cursor,
            'total': work.total,
            'complete': work.complete,
            'latencyMs': time.elapsedMilliseconds,
            'firstReadableMs': firstReadableMs,
            'firstCitationMs': firstCitationMs,
            'previewFramesBeforeFinal': previewFrames,
            'answer': frame.answer!.blocks
                .map(
                  (b) => {
                    'text': b.text,
                    'kind': b.kind.name,
                    'sources': b.sources.map((s) => s.id).toList(),
                  },
                )
                .toList(),
          });
          save();
          if (step == 0) {
            expect(work.cursor, 24);
            expect(frame.answer!.status, ChatAnswerStatus.partial);
            turn = await repo.continueExploration(latest, model: model);
          } else {
            expect(work.complete, isTrue);
            expect(work.cursor, 32);
          }
        }
        result['status'] = 'passed_structure_manual_quality_review_pending';
      } catch (e) {
        result['status'] = 'stopped_no_automatic_retry';
        result['errorType'] = e.runtimeType.toString();
        rethrow;
      } finally {
        save();
        context?.dispose();
        repo.dispose();
        await db.close();
        dio.close(force: true);
        lock.unlockSync();
        lock.closeSync();
        // Contains no credentials or HTTP headers.
        // ignore: avoid_print
        print('Adaptive diagnostic: ${report.path}');
      }
    },
    skip: Platform.environment['BOOK_CHAT_ADAPTIVE_LIVE'] != '1',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
