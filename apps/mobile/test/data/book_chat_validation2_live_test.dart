import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/models/ai_reply.dart';

import '../support/book_chat_dense.dart';
import '../support/book_chat_embedding_fallback.dart';
import '../support/book_chat_gold.dart';
import '../support/book_chat_heldout.dart';
import '../support/book_chat_refinement.dart';
import '../support/book_chat_retrieval.dart';
import '../support/book_chat_spike.dart';
import '../support/book_chat_validation2.dart';

void main() {
  test(
    'fresh book validation2: frozen refined pipeline, two fresh answer runs',
    () async {
      final protocol = verifyValidation2();
      verifyHeldoutProtocol();
      final key = Platform.environment['OPENROUTER_API_KEY'];
      if (key == null || key.isEmpty) throw StateError('local key required');
      final path =
          Platform.environment['BOOK_CHAT_VALIDATION2_REPORT'] ??
          '/tmp/luma-book-chat-validation2.json';
      if (File(path).existsSync()) {
        throw StateError('report exists; do not overwrite fresh evidence');
      }
      final data = validation2Corpus();
      final cases = validation2Inputs();
      final chunks = data.chunks;
      final corpus = chunks.map((s) => s.passage).toList();
      final byId = {for (final s in chunks) s.passage.id: s};
      final primaryQuery = {
        for (final c in cases) c.input.id: heldoutQuery(c.input, chunks),
      };
      final primaryCache = EmbeddingCache(
        File('/tmp/luma-book-chat-validation2-qwen.jsonl'),
        model: heldoutEmbeddingModel,
        dimensions: 4096,
      );
      final fallbackCache = LargeEmbeddingCache(
        File('/tmp/luma-book-chat-validation2-large.jsonl'),
      );
      final routing =
          (jsonDecode(
                File('test/fixtures/book_chat_validation2_protocol.json')
                    .readAsStringSync(),
              ) as Map)['embeddingRouting']
              as Map;
      final primaryUnavailable =
          routing['primaryUnavailableForThisEvaluation'] == true;
      EmbeddingCache cache = primaryUnavailable ? fallbackCache : primaryCache;
      String? fallbackReason = primaryUnavailable
          ? 'recorded_primary_provider_timeouts'
          : null;
      var query = {
        for (final e in primaryQuery.entries)
          e.key: embeddingQueryForModel(e.value, cache.model),
      };
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
          'experiment': 'fresh-book-validation2',
          'protocolHash': protocol,
          'startedAt': started,
          'independentValidation': true,
          'tunedAfterOpening': false,
          'embeddingModel': cache.model,
          'embeddingDimensions': cache.dimensions,
          'primaryEmbeddingModel': heldoutEmbeddingModel,
          'fallbackEmbeddingModel': largeEmbeddingModel,
          'fallbackReason': fallbackReason,
          'answerModel': heldoutAnswerModel,
          'embeddingRequests':
              primaryCache.newRequests + fallbackCache.newRequests,
          'primaryEmbeddingRequests': primaryCache.newRequests,
          'fallbackEmbeddingRequests': fallbackCache.newRequests,
          'embeddingLedger': cache.ledger,
          'chunkCount': corpus.length,
          'float32Bytes': cache.vectors.values.fold<int>(
            0,
            (n, v) => n + v.lengthInBytes,
          ),
          'twoRuns': 'Fresh selector and answer calls per case/run, no previous output in history; shared frozen embeddings.',
          'semanticReview': 'pending; range/IDs are proxies',
          'cases': rows,
        }),
      );
      checkpoint();
      try {
        final filled = await fillWithEmbeddingFallback(
          primary: primaryCache,
          fallback: fallbackCache,
          documents: corpus.map((p) => p.text).toList(),
          primaryQueries: primaryQuery.values.toList(),
          fallbackQueries: primaryQuery.values
              .map((q) => embeddingQueryForModel(q, largeEmbeddingModel))
              .toList(),
          live: true,
          apiKey: key,
          dio: dio,
          primaryUnavailable: primaryUnavailable,
        );
        cache = filled.cache;
        fallbackReason = filled.fallbackReason;
        query = {
          for (final e in primaryQuery.entries)
            e.key: embeddingQueryForModel(e.value, cache.model),
        };
      } on DioException catch (e) {
        checkpoint();
        fail(
          'embedding HTTP/transport ${e.response?.statusCode}/${e.type.name}',
        );
      }
      checkpoint();
      final gold = readGold(validation2File);
      final jobs = [
        for (final run in [1, 2])
          for (final c in cases) (run: run, c: c),
      ];
      var next = 0;
      String? abort;
      Future<void> worker() async {
        while (next < jobs.length && abort == null) {
          final job = jobs[next++];
          final c = job.c.input;
          final g = gold.firstWhere((g) => g.id == c.id);
          final row = <String, dynamic>{
            'run': job.run,
            'id': c.id,
            'book': c.book,
            'question': c.question,
            'factCount': g.facts.length,
          };
          rows.add(row);
          try {
            final quote = selectedWindow(c, chunks);
            final dense = denseSearch(
              corpus,
              cache,
              cache.vector(query[c.id]!),
              c.book,
              quoteId: quote,
              k: 40,
            );
            row['candidateRecall40'] = rangeRecall(
              g,
              dense.map((p) => byId[p.id]!),
            );
            final selectorInput = rerankUser(c, dense, quoteId: quote);
            row['selectorInputHash'] = textHash(selectorInput);
            checkpoint();
            final ranking = await evalStream(
              key: key,
              model: heldoutAnswerModel,
              system: rerankSystem,
              user: selectorInput,
              jsonOutput: true,
              maxTokens: 256,
            );
            row.addAll({
              'rerankRaw': ranking.text,
              'rerankUsage': ranking.usage,
              'rerankRequests': ranking.requests,
              'rerankMs': ranking.totalMs,
            });
            final sources = parseSelection(ranking.text, dense, quoteId: quote);
            final context = sources.map((p) => byId[p.id]!).toList();
            row.addAll({
              'finalRecall8': rangeRecall(g, context),
              'selectedIds': sources.map((p) => p.id).toList(),
              'sourceOwnershipValid': sources.every(
                (p) =>
                    p.book == c.book &&
                    p.revision == 1 &&
                    p.hash == textHash(p.text),
              ),
              'sources': [
                for (final (i, p) in sources.indexed)
                  {
                    'id': 'S${i + 1}',
                    'chunkId': p.id,
                    'book': p.book,
                    'text': p.text,
                    'hash': p.hash,
                    'ranges': [
                      for (final r in byId[p.id]!.ranges)
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
            final quoteText = job.c.selection?.quote;
            final user = focusedUser(
              c,
              sources,
              data.metadata[c.book]!,
              quoteId: quote,
              quoteText: quoteText,
            );
            row['answerInputHash'] = textHash(user);
            checkpoint();
            int? readable;
            final answer = await evalStream(
              key: key,
              model: heldoutAnswerModel,
              system: focusedAnswerSystem,
              user: user,
              jsonOutput: true,
              maxTokens: 800,
              onText: (text, ms) {
                try {
                  parseFocusedAnswer(text, sources, c.book);
                  readable ??= ms;
                } on FormatException {
                  /*hold incomplete JSON*/
                }
              },
            );
            row.addAll({
              'raw': answer.text,
              'answerUsage': answer.usage,
              'answerRequests': answer.requests,
              'answerMs': answer.totalMs,
              'firstContentMs': answer.firstMs,
              'firstReadableMs': readable,
            });
            final parsed = parseFocusedAnswer(answer.text, sources, c.book);
            final used = {
              for (final claim in parsed.claims)
                for (final ref in claim.sources)
                  int.parse(ref.id.substring(1)) - 1,
            };
            row.addAll({
              'valid': true,
              'status': parsed.status,
              'displayNote': parsed.note,
              'claims': [
                for (final claim in parsed.claims)
                  {
                    'text': claim.text,
                    'sourceIds': claim.sources.map((s) => s.id).toList(),
                  },
              ],
              'referencedGoldCoverage': rangeRecall(g, [
                for (final i in used) context[i],
              ]),
              'falseRefusal': g.facts.isNotEmpty && parsed.claims.isEmpty,
              'noSourceCorrect':
                  g.facts.isNotEmpty ||
                  (parsed.status == 'not_found' &&
                      parsed.claims.isEmpty &&
                      parsed.note == missingEvidenceNote),
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
            'fresh2 run${job.run} ${c.id}: selected=${row['finalRecall8']} referenced=${row['referencedGoldCoverage']} status=${row['status']} error=${row['error'] ?? '-'}',
          );
        }
      }

      await Future.wait([worker(), worker()]);
      checkpoint();
      expect(rows.length, 80, reason: 'abort=$abort $path');
      for (final run in [1, 2]) {
        final all = rows.where((r) => r['run'] == run).toList();
        final pos = all.where((r) => r['factCount'] > 0).toList();
        expect(
          all.where((r) => r['valid'] == true).length,
          greaterThanOrEqualTo(38),
          reason: path,
        );
        expect(
          pos.where((r) => r['finalRecall8'] == 1).length,
          greaterThanOrEqualTo(27),
          reason: 'selected evidence $path',
        );
        expect(
          pos.where((r) => r['referencedGoldCoverage'] == 1).length,
          greaterThanOrEqualTo(27),
          reason: 'referenced range proxy; manual review required $path',
        );
        expect(
          all
                  .where((r) => r['valid'] == true)
                  .every((r) => r['sourceOwnershipValid'] == true) &&
              all
                  .where((r) => r['factCount'] == 0)
                  .every((r) => r['noSourceCorrect'] == true),
          isTrue,
          reason: path,
        );
      }
      expect(verifyValidation2(), protocol);
    },
    skip: Platform.environment['BOOK_CHAT_VALIDATION2_LIVE'] != '1',
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
