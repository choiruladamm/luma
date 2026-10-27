import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/services/epub_parser.dart';
import 'package:luma/domain/models/ai_reply.dart';

import '../support/book_chat_dense.dart';
import '../support/book_chat_gold.dart';
import '../support/book_chat_heldout.dart';
import '../support/book_chat_refinement.dart';
import '../support/book_chat_retrieval.dart';
import '../support/book_chat_spike.dart';

void main() {
  test(
    'post-validation development: full-candidate selection and focused answers',
    () async {
      verifyHeldoutProtocol();
      final key = Platform.environment['OPENROUTER_API_KEY'];
      if (key == null || key.isEmpty) throw StateError('local key required');
      final path =
          Platform.environment['BOOK_CHAT_REFINEMENT_REPORT'] ??
          '/tmp/luma-book-chat-refinement-v1.json';
      if (File(path).existsSync()) {
        throw StateError('report exists; keep previous evidence');
      }
      final devParagraphs = loadParagraphs();
      final oldParagraphs = loadParagraphs(heldOut: true);
      final devChunks = [
        for (final g in groupedChunks(loadCorpus(), devParagraphs))
          if (g.passage.text.length <= 1800)
            g
          else
            ...windowChunks(
              g.ranges.map((r) => r.paragraph).toList(),
              size: 1800,
              overlap: 200,
            ),
      ];
      final oldChunks = heldoutChunks(oldParagraphs);
      final chunks = [...devChunks, ...oldChunks];
      final corpus = chunks.map((s) => s.passage).toList();
      final byId = {for (final s in chunks) s.passage.id: s};
      final devCache = EmbeddingCache(
        File('/tmp/luma-book-chat-qwen3-8b-v1.jsonl'),
        model: heldoutEmbeddingModel,
        dimensions: 4096,
      );
      final oldCache = EmbeddingCache(
        File('/tmp/luma-book-chat-heldout-qwen-v1.jsonl'),
        model: heldoutEmbeddingModel,
        dimensions: 4096,
      );
      final jobs = [
        for (final c in readCases())
          (input: c, selection: null, split: 'development'),
        for (final c in heldoutInputs())
          (
            input: c.input,
            selection: c.selection,
            split: 'consumed_diagnostic',
          ),
      ];
      final filter = Platform.environment['BOOK_CHAT_CASE'];
      final cases = jobs
          .where(
            (c) => filter == null || filter.split(',').contains(c.input.id),
          )
          .toList();
      final gold = [
        ...readGold('test/fixtures/book_chat_gold_v2.json'),
        ...readGold('test/fixtures/book_chat_held_out_v1.json'),
      ];
      final metadata = {
        for (final book in ['alice-in-wonderland', 'meditations'])
          book: parseEpub(File('test/fixtures/$book.epub').readAsBytesSync()),
      };
      final rows = <Map<String, dynamic>>[];
      final started = DateTime.now().toUtc().toIso8601String();
      void checkpoint() => File(path).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'experiment': 'post-validation-refinement-v1',
          'startedAt': started,
          'independentValidation': false,
          'retiredSplitUsedForDiagnostics': true,
          'freshHeldoutRuns': 0,
          'embeddingRequests': 0,
          'answerModel': heldoutAnswerModel,
          'rerankSystem': rerankSystem,
          'answerSystem': focusedAnswerSystem,
          'fixedNotes': {
            'not_found': missingEvidenceNote,
            'partial': partialEvidenceNote,
          },
          'sourceHashes': {
            for (final f in [
              'test/support/book_chat_refinement.dart',
              'test/data/book_chat_refinement_live_test.dart',
            ])
              f: textHash(File(f).readAsStringSync()),
          },
          'cases': rows,
        }),
      );
      var next = 0;
      String? abort;
      Future<void> worker() async {
        while (next < cases.length && abort == null) {
          final job = cases[next++];
          final c = job.input;
          final g = gold.firstWhere((g) => g.id == c.id);
          final row = <String, dynamic>{
            'id': c.id,
            'book': c.book,
            'split': job.split,
            'question': c.question,
            'factCount': g.facts.length,
          };
          rows.add(row);
          try {
            final owned = chunks
                .where((s) => s.passage.book == c.book)
                .toList();
            final quoteId = selectedWindow(c, owned);
            final cache = job.split == 'development' ? devCache : oldCache;
            // Cache misses fail; this experiment sends no embedding requests.
            final ranked = denseSearch(
              corpus,
              cache,
              cache.vector(heldoutQuery(c, owned)),
              c.book,
              quoteId: quoteId,
              k: 40,
            );
            final baseline = fitSources(ranked.take(8).toList());
            row['baselineRecall8'] = rangeRecall(
              g,
              baseline.map((p) => byId[p.id]!),
            );
            row['candidateRecall40'] = rangeRecall(
              g,
              ranked.map((p) => byId[p.id]!),
            );
            final rankingUser = rerankUser(c, ranked, quoteId: quoteId);
            row['rerankPromptBytes'] = bytes(rankingUser) + bytes(rerankSystem);
            checkpoint();
            final ranking = await evalStream(
              key: key,
              model: heldoutAnswerModel,
              system: rerankSystem,
              user: rankingUser,
              jsonOutput: true,
              maxTokens: 256,
            );
            row.addAll({
              'rerankRaw': ranking.text,
              'rerankUsage': ranking.usage,
              'rerankRequests': ranking.requests,
              'rerankMs': ranking.totalMs,
            });
            final sources = parseSelection(
              ranking.text,
              ranked,
              quoteId: quoteId,
            );
            final context = sources.map((p) => byId[p.id]!).toList();
            row.addAll({
              'finalRecall8': rangeRecall(g, context),
              'selectedIds': sources.map((s) => s.id).toList(),
              'sources': [
                for (final (i, s) in sources.indexed)
                  {
                    'id': 'S${i + 1}',
                    'chunkId': s.id,
                    'text': s.text,
                    'hash': s.hash,
                    'book': s.book,
                  },
              ],
              'sourceOwnershipValid': sources.every(
                (p) =>
                    p.book == c.book &&
                    p.revision == 1 &&
                    p.hash == textHash(p.text),
              ),
            });
            final outline = metadata[c.book];
            final book = outline == null
                ? bookMetadata(c.book)
                : {
                    'title': outline.title ?? c.book,
                    'author': outline.author ?? '',
                  };
            final quoteText =
                job.selection?.quote ??
                (quoteId == null
                    ? null
                    : ranked.firstWhere((p) => p.id == quoteId).text);
            final user = focusedUser(
              c,
              sources,
              book,
              quoteId: quoteId,
              quoteText: quoteText,
            );
            row['answerPromptBytes'] = bytes(user) + bytes(focusedAnswerSystem);
            checkpoint();
            final answer = await evalStream(
              key: key,
              model: heldoutAnswerModel,
              system: focusedAnswerSystem,
              user: user,
              jsonOutput: true,
              maxTokens: 800,
            );
            row.addAll({
              'raw': answer.text,
              'answerUsage': answer.usage,
              'answerRequests': answer.requests,
              'answerMs': answer.totalMs,
            });
            final parsed = parseFocusedAnswer(answer.text, sources, c.book);
            final used = {
              for (final claim in parsed.claims)
                for (final s in claim.sources) int.parse(s.id.substring(1)) - 1,
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
              'noSourceCorrect':
                  g.facts.isNotEmpty ||
                  (parsed.status == 'not_found' && parsed.claims.isEmpty),
              'falseRefusal': g.facts.isNotEmpty && parsed.claims.isEmpty,
            });
          } on FormatException catch (e) {
            row['error'] = e.message;
          } on AiException catch (e) {
            row['error'] = '${e.error.name}:${e.status ?? ''}';
            if ([401, 402, 403, 404].contains(e.status)) {
              abort = row['error'] as String;
            }
          } on StateError catch (e) {
            row['error'] = e.message;
            abort = row['error'] as String;
          }
          checkpoint();
          // ignore: avoid_print
          print(
            '${c.id}: baseline=${row['baselineRecall8']} reranked=${row['finalRecall8']} referenced=${row['referencedGoldCoverage']} status=${row['status']} error=${row['error'] ?? '-'}',
          );
        }
      }

      checkpoint();
      await Future.wait([worker(), worker()]);
      checkpoint();
      expect(rows.length, cases.length, reason: 'abort=$abort; $path');
      expect(
        rows.every(
          (r) => r['valid'] == true && r['sourceOwnershipValid'] == true,
        ),
        isTrue,
        reason: path,
      );
      verifyHeldoutProtocol();
      // Development outcomes are evidence, not independent validation or a reason to change gold.
    },
    skip: Platform.environment['BOOK_CHAT_REFINEMENT_LIVE'] != '1',
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
