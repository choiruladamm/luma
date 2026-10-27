import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/models/ai_reply.dart';

import '../support/book_chat_dense.dart';
import '../support/book_chat_gold.dart';
import '../support/book_chat_heldout.dart';
import '../support/book_chat_oracle.dart';
import '../support/book_chat_retrieval.dart';
import '../support/book_chat_spike.dart';

void main() {
  test(
    'frozen held-out pipeline: two fresh answer runs without tuning',
    () async {
      final protocolHash = verifyHeldoutProtocol();
      final key = Platform.environment['OPENROUTER_API_KEY'];
      if (key == null || key.isEmpty) {
        throw StateError('local API key required');
      }
      final path =
          Platform.environment['BOOK_CHAT_HELDOUT_REPORT'] ??
          '/tmp/luma-book-chat-heldout-v1.json';
      if (File(path).existsSync()) {
        throw StateError(
          'report already exists; never overwrite final evaluation evidence',
        );
      }
      final paragraphs = loadParagraphs(heldOut: true);
      final chunks = heldoutChunks(paragraphs);
      final corpus = chunks.map((s) => s.passage).toList();
      final byId = {for (final s in chunks) s.passage.id: s};
      final cases = heldoutInputs();
      final queries = {
        for (final c in cases) c.input.id: heldoutQuery(c.input, chunks),
      };
      final cache = EmbeddingCache(
        File(
          Platform.environment['BOOK_CHAT_HELDOUT_CACHE'] ??
              '/tmp/luma-book-chat-heldout-qwen-v1.jsonl',
        ),
        model: heldoutEmbeddingModel,
        dimensions: 4096,
      );
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://openrouter.ai/api/v1',
          connectTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      addTearDown(() => dio.close(force: true));
      final rows = <Map<String, dynamic>>[];
      final started = DateTime.now().toUtc().toIso8601String();
      void checkpoint() => File(path).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'experiment': 'held-out-v1',
          'protocolHash': protocolHash,
          'startedAt': started,
          'embeddingModel': heldoutEmbeddingModel,
          'answerModel': heldoutAnswerModel,
          'retrievalUsed': true,
          'oracleSourcesUsed': false,
          'pipelineTunedAfterOpening': false,
          'twoRunsMeaning': 'Two fresh answer requests per case, no prior-run outputs in history; deterministic retrieval shares frozen embeddings.',
          'embeddingRequests': cache.newRequests,
          'embeddingLedger': cache.ledger,
          'corpusHash': textHash(
            jsonEncode([
              for (final p in corpus) [p.id, p.hash],
            ]),
          ),
          'chunkCount': corpus.length,
          'float32Bytes': cache.vectors.values.fold<int>(
            0,
            (n, v) => n + v.lengthInBytes,
          ),
          'semanticReview': 'pending; source coverage is not entailment',
          'cases': rows,
        }),
      );
      checkpoint();
      try {
        await cache.fill(
          [...corpus.map((p) => p.text), ...queries.values],
          live: true,
          apiKey: key,
          dio: dio,
        );
      } on DioException catch (e) {
        checkpoint();
        fail(
          'held-out embedding HTTP/transport: ${e.response?.statusCode}/${e.type.name}; no automatic retry',
        );
      }
      checkpoint();
      final gold = readGold('test/fixtures/book_chat_held_out_v1.json');
      final jobs = [
        for (final run in [1, 2])
          for (final c in cases) (run: run, c: c),
      ];
      var next = 0;
      String? abort;
      Future<void> worker() async {
        while (next < jobs.length && abort == null) {
          final job = jobs[next++];
          final c = job.c;
          final g = gold.firstWhere((g) => g.id == c.input.id);
          final row = <String, dynamic>{
            'run': job.run,
            'id': c.input.id,
            'book': c.input.book,
            'question': c.input.question,
            'factCount': g.facts.length,
            'expectedStatus': g.status,
          };
          rows.add(row);
          try {
            final watch = Stopwatch()..start();
            final ranked = denseSearch(
              corpus,
              cache,
              cache.vector(queries[c.input.id]!),
              c.input.book,
              quoteId: selectedWindow(c.input, chunks),
              k: 40,
            );
            final sources = fitSources(ranked.take(8).toList());
            final context = sources.map((p) => byId[p.id]!).toList();
            row.addAll({
              'retrievalUs': watch.elapsedMicroseconds,
              'candidateRecall40': rangeRecall(
                g,
                ranked.map((p) => byId[p.id]!),
              ),
              'finalRecall8': rangeRecall(g, context),
              'sourceOwnershipValid': sources.every(
                (p) =>
                    p.book == c.input.book &&
                    p.revision == 1 &&
                    textHash(p.text) == p.hash,
              ),
              'candidateIds': ranked.map((p) => p.id).toList(),
              'sources': [
                for (final (i, s) in context.indexed)
                  {
                    'id': 'S${i + 1}',
                    'chunkId': s.passage.id,
                    'book': s.passage.book,
                    'text': s.passage.text,
                    'hash': s.passage.hash,
                    'ranges': [
                      for (final r in s.ranges)
                        {
                          'chapter': r.paragraph.chapter,
                          'paragraph': r.paragraph.index,
                          'start': r.start,
                          'end': r.end,
                          'paragraphHash': textHash(r.paragraph.text),
                        },
                    ],
                  },
              ],
            });
            final user = heldoutUser(c, sources, paragraphs);
            row['userPromptHash'] = textHash(user);
            row['promptBytes'] = bytes(user) + bytes(oracleJsonSystem);
            row['answerAttempted'] = true;
            checkpoint();
            int? readable;
            final reply = await evalStream(
              key: key,
              model: heldoutAnswerModel,
              system: oracleJsonSystem,
              user: user,
              jsonOutput: true,
              onText: (text, ms) {
                if (oraclePreview(text, sources, c.input.book).isNotEmpty) {
                  readable ??= ms;
                }
              },
            );
            row.addAll({
              'raw': reply.text,
              'usage': reply.usage,
              'requests': reply.requests,
              'firstContentMs': reply.firstMs,
              'firstReadableMs': readable,
              'totalMs': reply.totalMs,
            });
            final parsed = parseOracleJson(reply.text, sources, c.input.book);
            row.addAll({
              'valid': true,
              'status': parsed.status,
              'note': parsed.note,
              'claims': [
                for (final claim in parsed.claims)
                  {
                    'text': claim.text,
                    'sourceIds': claim.sources.map((s) => s.id).toList(),
                  },
              ],
              'referencedGoldCoverage': referencedRangeRecall(
                g,
                parsed.claims,
                context,
              ),
              'falseRefusal': g.facts.isNotEmpty && parsed.claims.isEmpty,
              'noSourceCorrect':
                  g.facts.isNotEmpty ||
                  (parsed.status == 'not_found' && parsed.claims.isEmpty),
            });
          } on FormatException catch (e) {
            row['error'] = e.message;
          } on AiException catch (e) {
            row['error'] = '${e.error.name}:${e.status ?? ''}';
            if ([401, 402, 403, 404].contains(e.status)) {
              abort = row['error'] as String;
            }
          }
          checkpoint();
          // ignore: avoid_print
          print(
            'heldout run${job.run} ${c.input.id}: coverage=${row['finalRecall8']} referenced=${row['referencedGoldCoverage']} valid=${row['valid']} status=${row['status']} error=${row['error'] ?? '-'}',
          );
        }
      }

      await Future.wait([worker(), worker()]);
      checkpoint();
      expect(rows.length, 80, reason: '$path; abort=$abort');
      for (final run in [1, 2]) {
        final all = rows.where((r) => r['run'] == run).toList();
        final positive = all.where((r) => r['factCount'] > 0).toList();
        expect(
          all.where((r) => r['valid'] == true).length,
          greaterThanOrEqualTo(38),
          reason: path,
        );
        expect(
          positive.where((r) => r['finalRecall8'] == 1).length,
          greaterThanOrEqualTo(27),
          reason: 'final evidence gate $path',
        );
        expect(
          positive
              .where(
                (r) =>
                    r['referencedGoldCoverage'] == 1 &&
                    r['falseRefusal'] == false,
              )
              .length,
          greaterThanOrEqualTo(27),
          reason: 'citation range proxy; semantic review still required: $path',
        );
        expect(
          all.every(
            (r) =>
                r['sourceOwnershipValid'] == true &&
                r['noSourceCorrect'] == true,
          ),
          isTrue,
          reason: path,
        );
      }
      expect(verifyHeldoutProtocol(), protocolHash);
    },
    skip: Platform.environment['BOOK_CHAT_HELDOUT_LIVE'] != '1',
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
