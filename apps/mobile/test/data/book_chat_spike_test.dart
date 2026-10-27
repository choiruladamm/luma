import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/book_chat_spike.dart';
import 'openrouter_service_test.dart' show FakeAdapter, sse, event;

void main() {
  late List<Passage> corpus;
  setUpAll(() => corpus = loadCorpus());

  test('fixture targets resolve before retrieval; measure unassisted baseline', () async {
    final cases = readCases();
    expect(cases.length, greaterThanOrEqualTo(24));
    final ids = corpus.map((p) => p.id).toSet();
    expect(ids.length, corpus.length);
    final rows = <Map<String, Object?>>[];
    for (final c in cases) {
      for (final alternatives in c.expected) {
        expect(alternatives.every(ids.contains), isTrue, reason: c.id);
      }
      final history = caseHistory(c);
      final result = await Isolate.run(() {
        final watch = Stopwatch()..start();
        final index = LexicalIndex(corpus, c.book, 1);
        final cold = watch.elapsedMicroseconds;
        watch.reset();
        final ranked = index.search(
          '${c.question} ${history.map((h) => '${h.question} ${h.answer}').join(' ')}',
          quoteId: c.quote,
        );
        return (
          ranked: ranked,
          coldUs: cold,
          warmUs: watch.elapsedMicroseconds,
        );
      });
      final selected = fitSources(result.ranked);
      expect(
        selected.every((p) => p.book == c.book && p.revision == 1),
        isTrue,
      );
      final prompt = userPrompt(
        c.question,
        history,
        selected,
        quoteId: c.quote,
      );
      expect(
        bytes(prompt) + bytes(answerSystem),
        lessThanOrEqualTo(promptBudget),
      );
      rows.add({
        'id': c.id,
        'expected': c.expected,
        'selected': selected.map((p) => p.id).toList(),
        'recall': recall(c.expected, selected),
        'coldUs': result.coldUs,
        'warmUs': result.warmUs,
      });
    }
    final answerable = rows
        .where((r) => (r['expected'] as List).isNotEmpty)
        .toList();
    final hits = answerable.where((r) => r['recall'] == 1.0).length;
    final report = {
      'cases': rows,
      'answerable': answerable.length,
      'completeRecallCases': hits,
      'passages': corpus.length,
      'sourceBytes': corpus.fold(0, (sum, p) => sum + bytes(p.text)),
      'platform': Platform.operatingSystem,
      'version': Platform.operatingSystemVersion,
    };
    final path = Platform.environment['BOOK_CHAT_BASELINE_REPORT'];
    if (path != null) {
      File(
        path,
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    }
    // ignore: avoid_print
    print(
      'BM25 original-language baseline: $hits/${answerable.length} complete recall; ${corpus.length} passages.',
    );
  });

  test(
    'filters book and revision before scoring, including selected quote',
    () {
      final p = corpus.first;
      final foreign = (
        id: 'foreign',
        book: 'foreign',
        revision: 1,
        chapter: 'f',
        from: 0,
        to: 0,
        text: p.text,
        hash: p.hash,
      );
      final stale = (
        id: 'stale',
        book: p.book,
        revision: 0,
        chapter: 'f',
        from: 0,
        to: 0,
        text: p.text,
        hash: p.hash,
      );
      final found = LexicalIndex(
        [p, foreign, stale],
        p.book,
        1,
      ).search(p.text, quoteId: 'foreign');
      expect(found, [p]);
      expect(LexicalIndex(corpus, 'missing', 1).search('Darcy'), isEmpty);
    },
  );

  test('history keeps only completed same-book/revision/session suffix within budget', () {
    const good = (
      book: 'a',
      revision: 1,
      session: 's',
      question: 'control?',
      answer: 'views',
      complete: true,
    );
    final history = [
      good,
      (
        book: 'b',
        revision: 1,
        session: 's',
        question: 'foreign',
        answer: 'secret',
        complete: true,
      ),
      (
        book: 'a',
        revision: 0,
        session: 's',
        question: 'stale',
        answer: 'secret',
        complete: true,
      ),
      (
        book: 'a',
        revision: 1,
        session: 'other',
        question: 'other',
        answer: 'secret',
        complete: true,
      ),
      (
        book: 'a',
        revision: 1,
        session: 's',
        question: 'partial',
        answer: 'secret',
        complete: false,
      ),
    ];
    expect(eligibleHistory(history, 'a', 1, 's'), [good]);
    expect(eligibleHistory(history, 'a', 1, 's', budget: 1), isEmpty);
    expect(
      eligibleHistory(List.filled(1000, good), 'a', 1, 's').length,
      lessThan(1000),
    );
  });

  test(
    'source budget keeps entire passages and never truncates quoted text',
    () {
      final p = corpus.first;
      expect(fitSources([p], budget: 1), isEmpty);
      expect(fitSources([p]), [p]);
      expect(
        jsonDecode(
          userPrompt('ini?', [], [p], quoteId: p.id),
        )['selectedSourceId'],
        'S1',
      );
      expect(
        () => userPrompt('ini?', [], [], quoteId: p.id),
        throwsFormatException,
      );
      expect(
        () => userPrompt('x' * (questionBudget + 1), [], []),
        throwsFormatException,
      );
      expect(() => userPrompt(' ', [], []), throwsFormatException);
      expect(
        () => userPrompt('é' * questionBudget, [], []),
        throwsFormatException,
      );
    },
  );

  test(
    'citation parser requires exact quote, candidate ID, and intact hash',
    () {
      final p = corpus.first;
      final quote = p.text.substring(0, 30);
      String answer(String id, String quote) =>
          '[BUKU]\n${jsonEncode({
            'claim': 'Contoh klaim',
            'sources': [
              {'id': id, 'quote': quote},
            ],
          })}\n';
      final valid = answer('S1', quote);
      for (var i = 0; i < valid.length; i++) {
        expect(draftClaims(valid.substring(0, i)), isEmpty);
      }
      expect(draftClaims(valid), ['Contoh klaim']);
      expect(parseAnswer(valid, [p]).claims.single.sources.single.quote, quote);
      expect(
        () => parseAnswer(answer('S999', quote), [p]),
        throwsFormatException,
      );
      expect(
        () => parseAnswer(answer('S1', 'A quotation not in this passage'), [p]),
        throwsFormatException,
      );
      expect(
        () => parseAnswer(valid, [
          (
            id: p.id,
            book: p.book,
            revision: p.revision,
            chapter: p.chapter,
            from: p.from,
            to: p.to,
            text: '${p.text}changed',
            hash: p.hash,
          ),
        ]),
        throwsFormatException,
      );
      expect(
        parseAnswer('[TIDAK_DITEMUKAN]\nBelum ada bukti.', []).claims,
        isEmpty,
      );
      expect(
        () => parseAnswer('$valid[TIDAK_DITEMUKAN]\nTidak ada.', [p]),
        throwsFormatException,
      );
      expect(() => parseAnswer('[BUKU]\n[BUKU]\n', [p]), throwsFormatException);
      expect(
        () => parseAnswer('[KONTEKS_TAMBAHAN]\nKlaim tanpa bukti', []),
        throwsFormatException,
      );
      expect(
        () => parseAnswer(valid.substring(0, valid.length - 4), [p]),
        throwsFormatException,
      );
    },
  );

  test('eval seam preserves model/reasoning, split SSE, usage and no-key zero network', () async {
    final adapter = FakeAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://openrouter.ai/api/v1'))
      ..httpClientAdapter = adapter;
    final stream =
        '${event('héllo')}data: {"choices":[],"usage":{"cost":0.001,"prompt_tokens":20,"completion_tokens":4}}\n\ndata: [DONE]\n\n';
    adapter.replies.add(sse([stream.substring(0, 12), stream.substring(12)]));
    final r = await evalStream(
      key: 'test',
      model: 'test-model',
      system: 'system',
      user: 'user',
      client: dio,
    );
    expect(r.text, 'héllo');
    expect(r.usage?['cost'], 0.001);
    expect(r.requests, 1);
    expect(adapter.requests.single.data['messages'], [
      {'role': 'system', 'content': 'system'},
      {'role': 'user', 'content': 'user'},
    ]);
    expect(adapter.requests.single.data['model'], 'test-model');
    expect(adapter.requests.single.data['reasoning'], {'enabled': false});
    final empty = FakeAdapter();
    await expectLater(
      evalStream(
        key: null,
        model: 'm',
        system: '',
        user: '',
        client: Dio()..httpClientAdapter = empty,
      ),
      throwsA(anything),
    );
    expect(empty.requests, isEmpty);
  });
}
