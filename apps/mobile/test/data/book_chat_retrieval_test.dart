import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/book_chat_gold.dart';
import '../support/book_chat_retrieval.dart';
import '../support/book_chat_spike.dart';

void main() {
  test(
    'windows preserve original text, bounds, overlap and complete coverage',
    () {
      final p = (
        book: 'test',
        chapter: 'one',
        index: 3,
        text: '${List.filled(150, 'word 😀').join(' ')} tail',
      );
      final chunks = windowChunks([p], size: 120, overlap: 20);
      expect(chunks.length, greaterThan(1));
      var end = 0;
      for (final c in chunks) {
        final r = c.ranges.single;
        expect(r.start, lessThanOrEqualTo(end));
        expect(c.passage.text, p.text.substring(r.start, r.end));
        expect(c.passage.text.length, lessThanOrEqualTo(120));
        expect(c.passage.hash, textHash(c.passage.text));
        expect(utf8.decode(utf8.encode(c.passage.text)), c.passage.text);
        end = r.end;
      }
      expect(end, p.text.length);
      expect(
        () => windowChunks([p], size: 100, overlap: 100),
        throwsArgumentError,
      );
    },
  );

  test(
    'range union requires no gaps and rejects stale or foreign paragraphs',
    () {
      const p = (book: 'test', chapter: 'one', index: 0, text: 'abcdefghij');
      final e = (
        book: 'test',
        revision: 1,
        chapter: 'one',
        paragraph: 0,
        start: 2,
        end: 8,
        hash: textHash(p.text),
        quote: 'cdefgh',
      );
      expect(
        rangesCover(e, [
          (paragraph: p, start: 0, end: 5),
          (paragraph: p, start: 5, end: 10),
        ]),
        isTrue,
      );
      expect(
        rangesCover(e, [
          (paragraph: p, start: 0, end: 4),
          (paragraph: p, start: 5, end: 10),
        ]),
        isFalse,
      );
      for (final bad in [
        (book: 'other', chapter: 'one', index: 0, text: p.text),
        (book: p.book, chapter: 'one', index: 0, text: 'changed!!!'),
      ]) {
        expect(rangesCover(e, [(paragraph: bad, start: 0, end: 10)]), isFalse);
      }
    },
  );

  test('query cleanup removes metadata noise while preserving asked names and negation', () {
    final base = readCases().first;
    expect(
      cleanRewrite(base, 'Epictetus Enchiridion not control'),
      'not control',
    );
    final asked = (
      id: base.id,
      book: base.book,
      question: 'Apa maksud Epictetus?',
      expected: base.expected,
      reason: base.reason,
      history: base.history,
      quote: base.quote,
    );
    expect(
      cleanRewrite(asked, 'Epictetus Enchiridion not control'),
      'Epictetus not control',
    );
    final name = readCases().firstWhere((c) => c.id == 'P02');
    expect(
      cleanRewrite(name, 'Darcy Elizabeth Jane Austen Pride Prejudice'),
      contains('Darcy Elizabeth'),
    );
  });

  test('development offline ablations replay queries without network or held-out input', () {
    final manifest = verifyEvalManifest();
    final watch = Stopwatch()..start();
    final paragraphs = loadParagraphs();
    final cases = readCases();
    final gold = readGold('test/fixtures/book_chat_gold_v2.json');
    final replayFile = File('test/fixtures/book_chat_rewrite_replay_v3.json');
    final replay = jsonDecode(replayFile.readAsStringSync()) as Map;
    final queries = replay['rewrites'] as Map;
    expect(queries.keys.toSet(), cases.map((c) => c.id).toSet());
    final groups = groupedChunks(loadCorpus(), paragraphs);
    final corpora = {
      'groups': groups,
      'bounded-groups-1800': [
        for (final group in groups)
          if (group.passage.text.length <= 1800)
            group
          else
            ...windowChunks(
              group.ranges.map((r) => r.paragraph).toList(),
              size: 1800,
              overlap: 200,
            ),
      ],
      for (final size in [600, 1200, 1800])
        'window-$size': windowChunks(paragraphs, size: size, overlap: 200),
    };
    final loadUs = watch.elapsedMicroseconds;
    final results = <Map<String, Object?>>[];
    for (final entry in corpora.entries) {
      final chunks = entry.value;
      final byId = {for (final c in chunks) c.passage.id: c};
      final build = Stopwatch()..start();
      final indices = {
        for (final book in cases.map((c) => c.book).toSet())
          book: LexicalIndex(chunks.map((c) => c.passage).toList(), book, 1),
      };
      final buildUs = build.elapsedMicroseconds;
      for (final clean in [false, true]) {
        final rows = <Map<String, Object?>>[];
        for (final c in cases) {
          final g = gold.firstWhere((g) => g.id == c.id);
          final raw = queries[c.id] as String;
          final rewrite = clean ? cleanRewrite(c, raw) : raw;
          final query = '${c.question} $rewrite';
          final quoteId = selectedWindow(c, chunks);
          if (c.quote != null) expect(quoteId, isNotNull);
          final search = Stopwatch()..start();
          final candidates = indices[c.book]!.search(
            query,
            quoteId: quoteId,
            k: 40,
          );
          final searchUs = search.elapsedMicroseconds;
          final selected = fitSources(candidates.take(8).toList());
          expect(
            candidates.every((p) => p.book == c.book && p.revision == 1),
            isTrue,
          );
          expect(selected.length, lessThanOrEqualTo(8));
          final top40 = rangeRecall(g, candidates.map((p) => byId[p.id]!));
          final top8 = rangeRecall(g, selected.map((p) => byId[p.id]!));
          rows.add({
            'id': c.id,
            'query': query,
            'quoteId': quoteId,
            'candidateRecall40': top40,
            'finalRecall8': top8,
            'searchUs': searchUs,
            'selectedBytes': selected.fold<int>(0, (n, p) => n + bytes(p.text)),
            'candidates': candidates.map((p) => p.id).toList(),
            'selected': selected.map((p) => p.id).toList(),
          });
        }
        int complete(String key) => rows.where((r) => r[key] == 1).length;
        results.add({
          'chunks': entry.key,
          'cleanQuery': clean,
          'chunkCount': chunks.length,
          'indexBuildUs': buildUs,
          'answerable': 22,
          'complete40': complete('candidateRecall40'),
          'complete8': complete('finalRecall8'),
          'cases': rows,
        });
      }
    }
    final report = {
      'protocol': 'offline-chunk-query-v1',
      'manifestHash': manifest,
      'replayHash': textHash(replayFile.readAsStringSync()),
      'requests': 0,
      'heldOutModelRuns': 0,
      'heldOutRetrievalRuns': 0,
      'note': 'Development tuning only. Source-range recall is not answer accuracy; negatives have null recall.',
      'platform': Platform.operatingSystem,
      'dart': Platform.version,
      'sourceBudgetBytes': sourceBudget,
      'loadUs': loadUs,
      'sourceRanges': {
        for (final entry in corpora.entries)
          entry.key: {
            for (final c in entry.value)
              c.passage.id: [
                for (final r in c.ranges)
                  {
                    'book': r.paragraph.book,
                    'chapter': r.paragraph.chapter,
                    'paragraph': r.paragraph.index,
                    'start': r.start,
                    'end': r.end,
                    'paragraphHash': textHash(r.paragraph.text),
                    'windowHash': c.passage.hash,
                  },
              ],
          },
      },
      'results': results,
    };
    final path =
        Platform.environment['BOOK_CHAT_RETRIEVAL_REPORT'] ??
        '/tmp/luma-book-chat-retrieval.json';
    File(path)
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    for (final r in results) {
      // ignore: avoid_print
      print(
        '${r['chunks']} clean=${r['cleanQuery']}: top40=${r['complete40']}/22 top8=${r['complete8']}/22',
      );
    }
    // No quality threshold: a failed experiment is evidence, not a reason to tune the gold.
    expect(results, hasLength(10));
    expect(verifyEvalManifest(), manifest);
  });
}
