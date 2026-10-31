import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/chat_context_repository.dart';
import 'package:luma/data/repositories/chat_repository.dart';
import 'package:luma/data/repositories/import_repository.dart';
import 'package:luma/data/services/api_key_store.dart';
import 'package:luma/data/services/file_storage.dart';
import 'package:luma/data/services/openrouter_service.dart';
import 'package:luma/domain/chat_exploration.dart';
import 'package:luma/domain/chat_prompt.dart';
import 'package:luma/domain/models/ai_reply.dart';
import 'package:luma/domain/models/book_chat.dart';

import '../support/book_chat_agent.dart';

class _Keys extends ApiKeyStore {
  _Keys(this.key);
  final String key;
  @override
  Future<String?> read() async => key;
}

/// #143 live evidence on a real EPUB through the production pipeline.
/// Paid opt-in: BOOK_CHAT_AGENT_LIVE=1, OPENROUTER_API_KEY, optional
/// OPENROUTER_MODEL, BOOK_CHAT_AGENT_BOOK (fixture name), BOOK_CHAT_AGENT_CASES
/// (comma separated indices), BOOK_CHAT_AGENT_TAG (report name),
/// BOOK_CHAT_AGENT_CONTINUE (max explicit continuations per case).
void main() {
  const cases = [
    'apa gagasan utama buku ini?',
    'bab III bahas apa? intinya apa?',
    'gue sering burnout kerja, ada saran dari buku ini?',
    'bedanya pandangan dia soal kematian sama Marcus Aurelius apa?',
  ];
  test('production pipeline on a real book (paid opt-in)', () async {
    final env = Platform.environment;
    if (env['BOOK_CHAT_AGENT_LIVE'] != '1') return;
    final key = env['OPENROUTER_API_KEY'];
    if (key == null || key.isEmpty) throw StateError('Local key required');
    final model = env['OPENROUTER_MODEL'] ?? 'z-ai/glm-5.3-flash';
    final bookFile = env['BOOK_CHAT_AGENT_BOOK'] ?? 'discourses.epub';
    final tag =
        env['BOOK_CHAT_AGENT_TAG'] ??
        'run-${DateTime.now().millisecondsSinceEpoch}';
    final maxContinue = int.parse(env['BOOK_CHAT_AGENT_CONTINUE'] ?? '2');
    // BOOK_CHAT_AGENT_QUESTIONS="q1|q2" replaces the case list (Meditations).
    final custom = env['BOOK_CHAT_AGENT_QUESTIONS'];
    final questions = custom == null || custom.isEmpty
        ? cases
        : custom.split('|');
    final selected = (env['BOOK_CHAT_AGENT_CASES'] ?? '0,1')
        .split(',')
        .map(int.parse)
        .toList();
    final report = File('test/fixtures/book_chat_agent_$tag.json');
    final ledger = AgentLedger(File('/tmp/luma-agent-ledger-$tag.json'));
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://openrouter.ai/api/v1',
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    final db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    final root = await Directory.systemTemp.createTemp('luma_agent_');
    final storage = FileStorage(root);
    await storage.ensureDirs();
    final repo = ChatRepository(db);
    ChatContextRepository? context;
    final results = <Map<String, Object?>>[];
    final result = <String, Object?>{
      'issue': 143,
      'model': model,
      'book': bookFile,
      'promptVersion': chatPromptVersion,
      'cases': results,
      'status': 'started',
    };
    void save() => report.writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert({
        ...result,
        'requests': ledger.rows,
        'heldUsd': ledger.heldUsd,
      }),
      flush: true,
    );
    try {
      final info = await agentModelInfo(dio, model);
      result['modelMetadata'] = {
        'context_length': info['context_length'],
        'pricing': info['pricing'],
        'reasoning': info['reasoning'],
      };
      final pricing = await agentPricing(dio, [
        model,
        for (final e in ChatEmbeddingModel.values) e.id,
      ]);
      dio.httpClientAdapter = AgentAdapter(
        dio.httpClientAdapter,
        ledger,
        pricing,
        onRow: (_) => save(),
      );
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/chat/completions') {
              final body = Map<String, dynamic>.from(options.data as Map);
              body['stream_options'] = {'include_usage': true};
              options.data = body;
            }
            handler.next(options);
          },
        ),
      );
      await db
          .into(db.settings)
          .insert(SettingsCompanion.insert(key: 'ai.model', value: model));
      final imported = await ImportRepository(db, storage).importEpub(
        File('test/fixtures/$bookFile').readAsBytesSync(),
        fileName: bookFile,
      );
      final book = await (db.select(
        db.books,
      )..where((b) => b.id.equals(imported.bookId))).getSingle();
      final chapters =
          await (db.select(db.chapters)
                ..where((c) => c.bookId.equals(book.id))
                ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
              .get();
      result['bookMetadata'] = {
        'title': book.title,
        'author': book.author,
        'totalChars': book.totalChars,
        'chapters': [
          for (final c in chapters)
            {'id': c.id, 'title': c.title, 'number': c.chapterNumber},
        ],
      };
      save();
      context = ChatContextRepository(
        db,
        repo,
        OpenRouterService(dio),
        _Keys(key),
      );
      final ref = (bookId: book.id, contentRevision: book.contentRevision);
      for (final index in selected) {
        // "pertanyaan>balasan" = turn lanjutan di sesi yang sama (klarifikasi).
        final chain = questions[index].split('>');
        final question = chain.first;
        final answerAt = int.tryParse(env['BOOK_CHAT_AGENT_ANSWER_AT'] ?? '');
        final row = <String, Object?>{
          'case': index,
          'question': question,
          'turns': <Map<String, Object?>>[],
        };
        results.add(row);
        final turns = row['turns'] as List<Map<String, Object?>>;
        final requestsBefore = ledger.rows.length;
        var turn = await repo.createFirstTurn(
          ref,
          question: question,
          model: model,
          promptVersion: chatPromptVersion,
        );
        var followUp = 1;
        for (var step = 0; step <= maxContinue + chain.length - 1; step++) {
          final time = Stopwatch()..start();
          final entry = <String, Object?>{
            'step': step,
            'question': turn.question,
          };
          turns.add(entry);
          final progress = <Map<String, Object?>>[];
          entry['progress'] = progress;
          try {
            final prepared = await context.prepare(
              turn,
              answerNow: () =>
                  answerAt != null &&
                  progress.isNotEmpty &&
                  (progress.last['completed'] as int) >= answerAt,
              onExplorationProgress: (p) => progress.add({
                'atMs': time.elapsedMilliseconds,
                'completed': p.completed,
                'total': p.total,
                'label': p.label,
                'notes': p.notes.length,
              }),
            );
            if (prepared == null) throw StateError('Preparation rejected');
            entry['prepareMs'] = time.elapsedMilliseconds;
            int? firstReadableMs;
            ChatStreamFrame? last;
            await for (final update in prepared.stream()) {
              last = update;
              if (update.answer == null &&
                  update.preview.any((b) => b.text.isNotEmpty)) {
                firstReadableMs ??= time.elapsedMilliseconds;
              }
            }
            final frame = last;
            if (frame?.answer == null) {
              throw StateError('No validated answer');
            }
            await repo.finalize(
              turn.attemptRef,
              phase: ChatPhase.done,
              draft: frame!.draft,
              answer: frame.answer,
            );
            entry.addAll({
              'status': frame.answer!.status.name,
              'latencyMs': time.elapsedMilliseconds,
              'firstReadableMs': firstReadableMs,
              'answer': [
                for (final b in frame.answer!.blocks)
                  {
                    'text': b.text,
                    'kind': b.kind.name,
                    'sources': b.sources.map((s) => s.id).toList(),
                  },
              ],
              'sources': [
                for (final s in prepared.prompt.sources)
                  {
                    'id': s.id,
                    'chapter': s.chapterTitle,
                    'paragraphs': [
                      s.anchors.first.paragraphIndex,
                      s.anchors.last.paragraphIndex,
                    ],
                  },
              ],
            });
          } on AiException catch (e) {
            await repo.finalize(
              turn.attemptRef,
              phase: ChatPhase.failed,
              error: e.error,
              httpStatus: e.status,
            );
            entry.addAll({
              'error': e.error.name,
              'detail': e.detail,
              'latencyMs': time.elapsedMilliseconds,
            });
          }
          final latest =
              (await repo.watchTurns(book.id, turn.sessionId).first).last;
          if (latest.exploration != null) {
            final work = ChatExploration.parse(latest.exploration!);
            entry['exploration'] = {
              'strategy': work.strategy.name,
              'cursor': work.cursor,
              'total': work.total,
              'complete': work.complete,
              'searched': work.searchedQueries,
              'pending': work.pendingQueries,
              'notes': work.notes.length,
            };
          }
          entry['requests'] = ledger.rows.length - requestsBefore;
          entry['heldUsd'] = ledger.heldUsd;
          save();
          if (chatCanContinue(latest) && step < maxContinue) {
            turn = await repo.continueExploration(latest, model: model);
            continue;
          }
          if (followUp < chain.length) {
            turn = await repo.appendTurn(
              ref,
              turn.sessionId,
              question: chain[followUp++],
              model: model,
              promptVersion: chatPromptVersion,
            );
            continue;
          }
          break;
        }
      }
      result['status'] = 'completed';
    } catch (e, s) {
      result['status'] = 'failed';
      result['failure'] = '$e\n$s';
      rethrow;
    } finally {
      save();
      context?.dispose();
      repo.dispose();
      await db.close();
      dio.close(force: true);
      await root.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 40)));
}
