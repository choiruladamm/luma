import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/book_chat_dense.dart';
import '../support/book_chat_gold.dart';
import '../support/book_chat_retrieval.dart';
import '../support/book_chat_spike.dart';

void main() {
  test(
    'development embedding dense and BM25 hybrid evaluation',
    () async {
      final manifest = verifyEvalManifest();
      final model =
          Platform.environment['BOOK_CHAT_EMBEDDING_MODEL'] ?? embeddingModel;
      final isQwen = model == 'qwen/qwen3-embedding-8b';
      final dimensions = isQwen ? 4096 : embeddingDimensions;
      final cacheName = isQwen ? 'qwen3-8b' : 'bge-m3';
      final paragraphs = loadParagraphs();
      final groups = groupedChunks(loadCorpus(), paragraphs);
      final chunks = [
        for (final group in groups)
          if (group.passage.text.length <= 1800)
            group
          else
            ...windowChunks(
              group.ranges.map((r) => r.paragraph).toList(),
              size: 1800,
              overlap: 200,
            ),
      ];
      final byId = {for (final c in chunks) c.passage.id: c};
      final corpus = chunks.map((c) => c.passage).toList();
      final cases = readCases();
      final rewrites =
          (jsonDecode(
                File('test/fixtures/book_chat_rewrite_replay_v3.json')
                    .readAsStringSync(),
              ) as Map)['rewrites']
              as Map;
      // No instruction prefix is required for BGE-M3 (official model card).
      final queries = {
        for (final c in cases)
          c.id: {
            'original': [
              for (final h in caseHistory(c))
                'Q: ${h.question}\nA: ${h.answer}',
              c.question,
              if (c.quote != null)
                byId[selectedWindow(c, chunks)]!.passage.text,
            ].join('\n'),
            'rewrite':
                '${c.question} ${cleanRewrite(c, rewrites[c.id] as String)}',
          },
      };
      if (isQwen) {
        for (final variants in queries.values) {
          variants.updateAll(
            (_, query) =>
                'Instruct: Given a question about a book, retrieve passages from that book that answer the question.\nQuery: $query',
          );
        }
      }
      final cache = EmbeddingCache(
        File(
          Platform.environment['BOOK_CHAT_EMBEDDING_CACHE'] ??
              '/tmp/luma-book-chat-$cacheName-v1.jsonl',
        ),
        model: model,
        dimensions: dimensions,
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
      final watch = Stopwatch()..start();
      try {
        await cache.fill(
          [
            ...corpus.map((p) => p.text),
            ...queries.values.expand((q) => q.values),
          ],
          live: Platform.environment['BOOK_CHAT_EMBEDDING_LIVE'] == '1',
          apiKey: Platform.environment['OPENROUTER_API_KEY'],
          dio: dio,
        );
      } on DioException catch (e) {
        fail(
          'embedding HTTP/transport failure: status=${e.response?.statusCode}, type=${e.type.name}; no automatic retry',
        );
      }
      final embeddingMs = watch.elapsedMilliseconds;
      // Gold is loaded only after embeddings; never enters the input list or ranking.
      final gold = readGold('test/fixtures/book_chat_gold_v2.json');
      final lexical = {
        for (final book in cases.map((c) => c.book).toSet())
          book: LexicalIndex(corpus, book, 1),
      };
      final results = <Map<String, Object?>>[];
      for (final queryMode in ['original', 'rewrite']) {
        for (final hybrid in [false, true]) {
          final rows = <Map<String, Object?>>[];
          for (final c in cases) {
            final quote = selectedWindow(c, chunks);
            watch.reset();
            final dense = denseSearch(
              corpus,
              cache,
              cache.vector(queries[c.id]![queryMode]!),
              c.book,
              quoteId: quote,
              k: hybrid ? 20 : 40,
            );
            final ranked = hybrid
                ? fuseRanks(
                    lexical[c.book]!.search(
                      '${c.question} ${cleanRewrite(c, rewrites[c.id] as String)}',
                      quoteId: quote,
                      k: 20,
                    ),
                    dense,
                    quoteId: quote,
                  )
                : dense;
            final searchUs = watch.elapsedMicroseconds;
            final selected = fitSources(ranked.take(8).toList());
            expect(
              ranked.every((p) => p.book == c.book && p.revision == 1),
              isTrue,
            );
            final g = gold.firstWhere((g) => g.id == c.id);
            rows.add({
              'id': c.id,
              'candidateRecall': rangeRecall(g, ranked.map((p) => byId[p.id]!)),
              'finalRecall8': rangeRecall(g, selected.map((p) => byId[p.id]!)),
              'searchUs': searchUs,
              'query': queries[c.id]![queryMode],
              'candidates': ranked.map((p) => p.id).toList(),
              'selected': selected.map((p) => p.id).toList(),
            });
          }
          final result = {
            'queryMode': queryMode,
            'hybrid': hybrid,
            'completeCandidates': rows
                .where((r) => r['candidateRecall'] == 1)
                .length,
            'complete8': rows.where((r) => r['finalRecall8'] == 1).length,
            'cases': rows,
          };
          results.add(result);
          // ignore: avoid_print
          print(
            '$model $queryMode hybrid=$hybrid: candidates=${result['completeCandidates']}/22 final8=${result['complete8']}/22',
          );
        }
      }
      final report = {
        'protocol': 'embedding-hybrid-v1',
        'manifestHash': manifest,
        'model': model,
        'dimensions': dimensions,
        'chunking': 'bounded-groups-1800 overlap200',
        'chunkCount': chunks.length,
        'corpusHash': textHash(
          jsonEncode([
            for (final p in corpus) [p.id, p.hash],
          ]),
        ),
        'rrfK': 60,
        'denseCandidates': 20,
        'bm25Candidates': 20,
        'heldOutModelRuns': 0,
        'heldOutRetrievalRuns': 0,
        'answerModelRuns': 0,
        'newEmbeddingRequests': cache.newRequests,
        'newInputBytes': cache.newInputBytes,
        'embeddingOrCacheLoadMs': embeddingMs,
        'cacheVectorCount': cache.vectors.length,
        'float32Bytes': cache.vectors.values.fold<int>(
          0,
          (n, v) => n + v.lengthInBytes,
        ),
        'embeddingLedger': cache.ledger,
        'platform': Platform.operatingSystem,
        'note': 'Development source-range coverage only. Not answer accuracy; no-source recall is null. Dense-only uses top40; hybrid unions top20+top20.',
        'results': results,
      };
      File(
        Platform.environment['BOOK_CHAT_DENSE_REPORT'] ??
            '/tmp/luma-book-chat-dense-$cacheName.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
      expect(verifyEvalManifest(), manifest);
    },
    skip: Platform.environment['BOOK_CHAT_EMBEDDING_RUN'] != '1',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
