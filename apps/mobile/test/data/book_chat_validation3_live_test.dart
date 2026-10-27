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
import '../support/book_chat_recovery.dart';
import '../support/book_chat_spike.dart';
import '../support/book_chat_validation3.dart';

void main() {
  test(
    'fresh validation3: frozen translated hybrid pipeline, two complete runs',
    () async {
      final protocol = verifyValidation3();
      verifyHeldoutProtocol();
      final key = Platform.environment['OPENROUTER_API_KEY'];
      if (key == null || key.isEmpty) throw StateError('local key required');
      final path =
          Platform.environment['BOOK_CHAT_VALIDATION3_REPORT'] ??
          '/tmp/luma-book-chat-validation3.json';
      if (File(path).existsSync()) {
        throw StateError('report exists; do not overwrite fresh evidence');
      }
      final data = validation3Corpus();
      final cases = validation3Inputs();
      final chunks = data.chunks;
      final corpus = chunks.map((s) => s.passage).toList();
      final byId = {for (final s in chunks) s.passage.id: s};
      final primaryQuery = {
        for (final c in cases) c.input.id: heldoutQuery(c.input, chunks),
      };
      final cache = LargeEmbeddingCache(
        File('/tmp/luma-book-chat-validation3-large.jsonl'),
      );
      final rewrites = <String, String>{};
      final needsClarification = <String>{};
      var query = {
        for (final e in primaryQuery.entries)
          e.key: embeddingQueryForModel(e.value, largeEmbeddingModel),
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
          'experiment': 'fresh-book-validation3',
          'protocolHash': protocol,
          'sourceHashes': {
            for (final f in [
              'test/support/book_chat_recovery.dart',
              'test/data/book_chat_validation3_live_test.dart',
            ])
              f: textHash(File(f).readAsStringSync()),
          },
          'startedAt': started,
          'independentValidation': true,
          'tunedAfterOpening': false,
          'embeddingModel': cache.model,
          'embeddingDimensions': cache.dimensions,
          'embeddingRequests': cache.newRequests,
          'rewrites': rewrites,
          'needsClarification': needsClarification.toList(),
          'embeddingLedger': cache.ledger,
          'chunkCount': corpus.length,
          'float32Bytes': cache.vectors.values.fold<int>(
            0,
            (n, v) => n + v.lengthInBytes,
          ),
          'twoRuns': 'Fresh rewrite, selector and answer calls per case/run; no prior run output in history, shared document/original-query embedding cache.',
          'semanticReview': 'pending; range/IDs are proxies',
          'cases': rows,
        }),
      );
      checkpoint();
      // Translation uses question/history/user-selected text only, never gold.
      for (final rewriteJob in [
        for (final run in [1, 2])
          for (final c in cases) (run: run, c: c),
      ]) {
        final job = rewriteJob.c;
        final planId = "${rewriteJob.run}:${job.input.id}";
        final c = job.input;
        final quote = selectedWindow(c, chunks);
        final selectedText =
            job.selection?.quote ??
            (quote == null ? null : byId[quote]!.passage.text);
        final reply = await evalStream(
          key: key,
          model: heldoutAnswerModel,
          system: searchRewriteSystem,
          user: searchRewriteUser(c, selectedQuote: selectedText),
          jsonOutput: true,
          maxTokens: 256,
        );
        rows.add({
          'phase': 'rewrite',
          'rewriteRun': rewriteJob.run,
          'id': c.id,
          'raw': reply.text,
          'usage': reply.usage,
          'requests': reply.requests,
          'ms': reply.totalMs,
        });
        checkpoint();
        final plan = parseSearchRewrite(reply.text);
        rewrites[planId] = plan.query;
        if (plan.needsClarification) needsClarification.add(planId);
      }
      await cache.fill(
        [...corpus.map((p) => p.text), ...query.values, ...rewrites.values],
        live: true,
        apiKey: key,
        dio: dio,
      );
      checkpoint();
      final gold = readGold(validation3File);
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
          final planId = "${job.run}:${c.id}";
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
            if (needsClarification.contains(planId)) {
              row.addAll({
                'needsClarification': true,
                'valid': true,
                'status': 'not_found',
                'displayNote': missingEvidenceNote,
                'claims': <Object>[],
                'sources': <Object>[],
                'selectedIds': <String>[],
                'sourceOwnershipValid': true,
                'finalRecall8': g.facts.isEmpty ? null : 0.0,
                'referencedGoldCoverage': g.facts.isEmpty ? null : 0.0,
                'falseRefusal': g.facts.isNotEmpty,
                'noSourceCorrect': true,
                'selectionAnswerRequests': 0,
              });
              checkpoint();
              continue;
            }
            final quote = selectedWindow(c, chunks);
            final original = denseSearch(
              corpus,
              cache,
              cache.vector(query[c.id]!),
              c.book,
              quoteId: quote,
              k: 40,
            );
            final translated = denseSearch(
              corpus,
              cache,
              cache.vector(rewrites[planId]!),
              c.book,
              quoteId: quote,
              k: 40,
            );
            final lexical = LexicalIndex(
              corpus,
              c.book,
              1,
            ).search(rewrites[planId]!, quoteId: quote, k: 40);
            final dense = recoveryCandidates(c, [
              original,
              translated,
              lexical,
            ], quoteId: quote);
            row['originalCandidateRecall40'] = rangeRecall(
              g,
              original.map((p) => byId[p.id]!),
            );
            row['translatedCandidateRecall40'] = rangeRecall(
              g,
              translated.map((p) => byId[p.id]!),
            );
            row['lexicalCandidateRecall40'] = rangeRecall(
              g,
              lexical.map((p) => byId[p.id]!),
            );
            row['needsClarification'] = needsClarification.contains(planId);
            row['candidateRecall40'] = rangeRecall(
              g,
              dense.map((p) => byId[p.id]!),
            );
            final selectorInput = rerankUser(c, dense, quoteId: quote);
            if (bytes(selectorInput) + bytes(recoverySelectionSystem) > 90000) {
              throw const FormatException('recovery selector budget');
            }
            row['selectorInputHash'] = textHash(selectorInput);
            checkpoint();
            final ranking = await evalStream(
              key: key,
              model: heldoutAnswerModel,
              system: recoverySelectionSystem,
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
            if (bytes(user) + bytes(recoveryAnswerSystem) > promptBudget) {
              throw const FormatException('recovery answer budget');
            }
            row['answerInputHash'] = textHash(user);
            checkpoint();
            int? readable;
            final answer = await evalStream(
              key: key,
              model: heldoutAnswerModel,
              system: recoveryAnswerSystem,
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
            'fresh3 run${job.run} ${c.id}: selected=${row['finalRecall8']} referenced=${row['referencedGoldCoverage']} status=${row['status']} error=${row['error'] ?? '-'}',
          );
        }
      }

      await Future.wait([worker(), worker()]);
      checkpoint();
      expect(
        rows.length,
        160,
        reason: '80 rewrites + 80 fresh answer outcomes; abort=$abort $path',
      );
      for (final run in [1, 2]) {
        final all = rows.where((r) => r['run'] == run).toList();
        final pos = all.where((r) => r['factCount'] > 0).toList();
        expect(all.length, 40, reason: path);
        expect(
          all.where((r) => r['valid'] == true).length,
          greaterThanOrEqualTo(38),
          reason: path,
        );
        expect(
          pos.where((r) => r['finalRecall8'] == 1).length,
          greaterThanOrEqualTo(27),
          reason: 'selected evidence: $path',
        );
        expect(
          pos.where((r) => r['referencedGoldCoverage'] == 1).length,
          greaterThanOrEqualTo(27),
          reason: 'referenced range proxy, manual review required: $path',
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
      expect(verifyValidation3(), protocol);
    },
    skip: Platform.environment['BOOK_CHAT_VALIDATION3_LIVE'] != '1',
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
