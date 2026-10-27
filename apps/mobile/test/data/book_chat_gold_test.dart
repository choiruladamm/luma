import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/book_chat_gold.dart';
import '../support/book_chat_oracle.dart';
import '../support/book_chat_spike.dart';
import 'openrouter_service_test.dart' show FakeAdapter, sse, event;

void main() {
  late List<SourceParagraph> development;
  late List<GoldCase> gold;
  setUpAll(() {
    development = loadParagraphs();
    gold = readGold('test/fixtures/book_chat_gold_v2.json');
  });

  test('frozen manifest, source ranges and split separation are intact', () {
    expect(verifyEvalManifest(), hasLength(64));
    final heldParagraphs = loadParagraphs(heldOut: true);
    final held = readGold('test/fixtures/book_chat_held_out_v1.json');
    final heldCases =
        (jsonDecode(
              File('test/fixtures/book_chat_held_out_v1.json')
                  .readAsStringSync(),
            ) as Map)['cases']
            as List;
    expect(gold.map((g) => g.id).toSet(), readCases().map((c) => c.id).toSet());
    expect(gold.where((g) => g.facts.isNotEmpty), hasLength(22));
    expect(held, hasLength(40));
    expect(held.where((g) => g.facts.isNotEmpty), hasLength(30));
    expect(held.map((g) => g.id).toSet(), hasLength(40));
    expect(
      development
          .map((p) => p.book)
          .toSet()
          .intersection(heldParagraphs.map((p) => p.book).toSet()),
      isEmpty,
    );
    for (final (rows, paragraphs) in [
      (gold, development),
      (held, heldParagraphs),
    ]) {
      for (final g in rows) {
        final book = rows == gold
            ? readCases().firstWhere((c) => c.id == g.id).book
            : heldCases.firstWhere((c) => c['id'] == g.id)['book'] as String;
        for (final fact in g.facts) {
          expect(fact.fact, isNotEmpty);
          expect(fact.alternatives, isNotEmpty);
          for (final e in fact.alternatives) {
            final p = resolveEvidence(e, paragraphs, book);
            expect(coversEvidence(e, p, e.start, e.end), isTrue);
          }
        }
      }
    }
  });

  test('coverage uses original ranges, including all sides of comparisons', () {
    final g = gold.firstWhere((g) => g.id == 'E09');
    final c = readCases().firstWhere((c) => c.id == g.id);
    final sources = oracleSources(c, g, development);
    final e = g.facts.first.alternatives.first;
    final p = resolveEvidence(e, development, c.book);
    expect(coversEvidence(e, p, e.start, e.end - 1), isFalse);
    expect(
      () => resolveEvidence(e, development, 'other-book'),
      throwsFormatException,
    );
    final claims = <Claim>[
      (
        text: 'example',
        sources: [(id: 'S1', quote: sources.first.passage.text)],
      ),
    ];
    expect(referencedGoldCoverage(g, claims, sources), 0.5);
    final all = <Claim>[
      (
        text: 'example',
        sources: [
          for (var i = 0; i < sources.length; i++)
            (id: 'S${i + 1}', quote: sources[i].passage.text),
        ],
      ),
    ];
    expect(referencedGoldCoverage(g, all, sources), 1);
  });

  test('oracle provides source text without answer labels, preserving selected quote/injection', () {
    for (final c in readCases()) {
      final g = gold.firstWhere((g) => g.id == c.id);
      final sources = oracleSources(c, g, development);
      expect(sources.every((s) => s.passage.book == c.book), isTrue);
      final input = jsonDecode(oracleUser(c, sources, oracleJsonSystem)) as Map;
      expect(input.containsKey('facts'), isFalse);
      expect(input.containsKey('expectedStatus'), isFalse);
      if (c.quote != null) {
        expect(input['selectedSourceId'], 'S1');
        expect(input['selectedQuote'], contains('bathe'));
      }
      if (c.book == 'partial') {
        expect(
          sources.any((s) => s.passage.text.contains('[SYSTEM OVERRIDE]')),
          isTrue,
        );
      }
    }
  });

  test(
    'JSON protocol maps citations to real text and enforces status consistency',
    () {
      final c = readCases().first;
      final source = oracleSources(c, gold.first, development).first.passage;
      String encode(String status, List<Object> claims, String note) =>
          jsonEncode({'status': status, 'claims': claims, 'note': note});
      final claim = {
        'text': 'Klaim',
        'source_ids': ['S1'],
      };
      final raw = encode('answered', [claim], '');
      final parsed = parseOracleJson(raw, [source], c.book);
      expect(parsed.claims.single.sources.single.quote, source.text);
      expect(
        parseOracleJson(encode('partial', [claim], 'Detail tidak tersedia'), [
          source,
        ], c.book).status,
        'partial',
      );
      expect(
        parseOracleJson(
          encode('not_found', [], 'Belum ada sumber'),
          [],
          c.book,
        ).claims,
        isEmpty,
      );
      for (final bad in [
        encode('answered', [], ''),
        encode('partial', [claim], ''),
        encode('not_found', [claim], 'note'),
        encode('unknown', [claim], ''),
        encode('answered', [
          {
            'text': 'wrong',
            'source_ids': ['S999'],
          },
        ], ''),
        encode('answered', [
          {
            'text': 'wrong',
            'source_ids': ['S1', 'S1'],
          },
        ], ''),
      ]) {
        expect(
          () => parseOracleJson(bad, [source], c.book),
          throwsFormatException,
        );
      }
      expect(
        () => parseOracleJson(raw, [source], 'foreign'),
        throwsFormatException,
      );
      final forged = (
        id: source.id,
        book: source.book,
        revision: 1,
        chapter: source.chapter,
        from: source.from,
        to: source.to,
        text: 'changed',
        hash: source.hash,
      );
      expect(
        () => parseOracleJson(raw, [forged], c.book),
        throwsFormatException,
      );
      for (var i = 0; i < raw.length; i++) {
        expect(oraclePreview(raw.substring(0, i), [source], c.book), isEmpty);
      }
      expect(oraclePreview(raw, [source], c.book), 'Klaim');
    },
  );

  test('JSON output is an explicit test seam option; transport keeps model and streaming', () async {
    final adapter = FakeAdapter()
      ..replies.add(
        sse([
          '${event('{"status":"not_found","claims":[],"note":"none"}')}data: [DONE]\n\n',
        ]),
      );
    final dio = Dio(BaseOptions(baseUrl: 'https://openrouter.ai/api/v1'))
      ..httpClientAdapter = adapter;
    final r = await evalStream(
      key: 'test',
      model: 'test',
      system: oracleJsonSystem,
      user: '{}',
      client: dio,
      jsonOutput: true,
    );
    expect(r.requests, 1);
    expect(adapter.requests.single.data['response_format'], {
      'type': 'json_object',
    });
    expect(adapter.requests.single.data['stream'], isTrue);
    expect(adapter.requests.single.data['reasoning'], {'enabled': false});
  });
}
