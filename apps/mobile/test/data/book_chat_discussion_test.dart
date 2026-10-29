import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/book_chat_discussion.dart';
import '../support/book_chat_spike.dart';
import 'openrouter_service_test.dart' show FakeAdapter, sse, event;

void main() {
  late Directory dir;
  late DiscussionBudget budget;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('luma-discussion-test-');
    budget = DiscussionBudget(File('${dir.path}/ledger.json'));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'real-book oracle sources match originals and labels never enter payload',
    () {
      final file = File('test/fixtures/book_chat_discussion_real_cases.json');
      final corpus = jsonDecode(file.readAsStringSync()) as Map;
      final protocol = jsonDecode(
        File('test/fixtures/book_chat_discussion_protocol.json')
            .readAsStringSync(),
      ) as Map;
      expect(
        sha256.convert(file.readAsBytesSync()).toString(),
        protocol['realCorpusSha256'],
      );
      final books = corpus['books'] as List;
      expect(books.map((b) => b['id']).toSet(), hasLength(2));
      final cases = corpus['cases'] as List;
      expect(cases.map((c) => c['id']).toSet(), hasLength(20));
      for (final book in books) {
        final bookFile = File('test/fixtures/${book['id']}.epub');
        expect(
          sha256.convert(bookFile.readAsBytesSync()).toString(),
          book['sha256'],
        );
        final paragraphs = discussionParagraphs(book['id'] as String);
        final rows = cases.where((c) => c['book'] == book['id']).toList();
        expect(
          rows,
          hasLength(protocol['realCorpusCounts'][book['split']] as int),
        );
        for (final row in rows) {
          expect(row['split'], book['split']);
          final sources = discussionSources(row as Map, paragraphs);
          final user = discussionUser(row, book['title'] as String, sources);
          final payload = jsonDecode(user) as Map;
          expect(payload.keys.toSet(), {
            'book',
            'question',
            'history',
            'sources',
          });
          final poisoned = Map.from(row)
            ..['gold'] = {'secret': 'GOLD_SENTINEL'}
            ..['category'] = 'CATEGORY_SENTINEL';
          expect(
            discussionUser(poisoned, book['title'] as String, sources),
            user,
          );
          final audit = jsonDecode(
            discussionUser(
              poisoned,
              book['title'] as String,
              sources,
              draftToReview: 'Untrusted candidate, not book evidence',
            ),
          ) as Map;
          expect(
            audit.remove('draftToReview'),
            'Untrusted candidate, not book evidence',
          );
          expect(audit, payload);
          final wrongBook = paragraphs
              .map(
                (p) => (
                  book: 'foreign',
                  chapter: p.chapter,
                  index: p.index,
                  text: p.text,
                ),
              )
              .toList();
          expect(() => discussionSources(row, wrongBook), throwsStateError);
          final stale = paragraphs
              .map(
                (p) => (
                  book: p.book,
                  chapter: p.chapter,
                  index: p.index,
                  text: '${p.text}!',
                ),
              )
              .toList();
          expect(() => discussionSources(row, stale), throwsFormatException);
        }
      }
    },
  );

  test(
    'natural answers allow interpretation but reject fabricated citation IDs',
    () {
      Map<String, Object> part(String kind, List<String> ids) => {
        'text': 'Uraian',
        'kind': kind,
        'source_ids': ids,
      };
      String answer(List<Object> parts) =>
          jsonEncode({'status': 'answered', 'parts': parts});
      expect(
        parseDiscussionAnswer(
          answer([
            part('book', ['S1']),
            part('interpretation', []),
            part('external', []),
          ]),
          {'S1'},
        )['parts'],
        hasLength(3),
      );
      for (final parts in [
        <Object>[],
        [part('book', [])],
        [
          part('book', ['S99']),
        ],
        [
          part('book', ['S1', 'S1']),
        ],
        [
          part('external', ['S1']),
        ],
      ]) {
        expect(
          () => parseDiscussionAnswer(answer(parts), {'S1'}),
          throwsFormatException,
        );
      }
    },
  );

  test('duplicate JSON keys cannot silently discard caveats or citations', () {
    for (final raw in [
      r'{"status":"partial","parts":[{"text":"Context is incomplete","kind":"conversation","source_ids":[]}],"parts":[{"text":"Book fact","kind":"book","source_ids":["S1"]}]}',
      r'{"status":"answered","parts":[{"text":"Fact","kind":"book","source_ids":["S1"],"source_ids":["S1"]}]}',
      r'{"status":"answered","parts":[],"pa\u0072ts":[{"text":"Fact","kind":"book","source_ids":["S1"]}]}',
    ]) {
      expect(() => parseDiscussionAnswer(raw, {'S1'}), throwsFormatException);
    }
    final valid = jsonEncode({
      'status': 'answered',
      'parts': [
        {
          'text': 'Braces { } and comma , in a string',
          'kind': 'book',
          'source_ids': ['S1'],
        },
        {
          'text': 'Same keys in another object',
          'kind': 'interpretation',
          'source_ids': ['S1'],
        },
      ],
    });
    expect(parseDiscussionAnswer(valid, {'S1'})['parts'], hasLength(2));
  });

  test('mandatory reasoning uses lowest advertised effort before dispatch', () {
    expect(
      discussionReasoning({
        'reasoning': {'mandatory': false},
      }),
      {'enabled': false},
    );
    expect(
      discussionReasoning({
        'reasoning': {
          'mandatory': true,
          'supported_efforts': ['max', 'high', 'low'],
        },
      }),
      {'effort': 'low', 'exclude': true},
    );
    expect(
      () => discussionReasoning({
        'reasoning': {'mandatory': true},
      }),
      throwsStateError,
    );
    expect(
      () => discussionReasoning({
        'reasoning': {
          'mandatory': true,
          'supported_efforts': ['none'],
        },
      }),
      throwsStateError,
    );
  });

  test(
    'budget survives reopen, never refunds missing usage and stops before cap',
    () {
      final index = budget.reserve(
        contextLength: 4000000,
        maxTokens: 3000,
        model: 'model',
      );
      expect(DiscussionBudget(budget.file).heldUsd, closeTo(2.006, 0.00001));
      budget.settle(index, null);
      expect(budget.heldUsd, closeTo(2.006, 0.00001));
      budget.reserve(contextLength: 4000000, maxTokens: 3000, model: 'model');
      expect(
        () => budget.reserve(
          contextLength: 4000000,
          maxTokens: 3000,
          model: 'model',
        ),
        throwsStateError,
      );
      expect(budget.rows, hasLength(2));
      expect(() => budget.settle(index, {'cost': 0}), throwsStateError);
    },
  );

  test(
    'actual accounting releases reservation only for bounded finite cost',
    () {
      final index = budget.reserve(
        contextLength: 1000000,
        maxTokens: 3000,
        model: 'model',
      );
      for (final cost in [-1, double.nan, double.infinity, 10]) {
        expect(() => budget.settle(index, {'cost': cost}), throwsStateError);
        expect(budget.heldUsd, closeTo(0.506, 0.00001));
      }
      budget.settle(index, {'cost': 0.01});
      expect(DiscussionBudget(budget.file).heldUsd, 0.01);
      expect(
        () =>
            budget.reserve(contextLength: 10, maxTokens: 3001, model: 'model'),
        throwsStateError,
      );
    },
  );

  test('lower price caps never reduce an existing unknown reservation', () {
    budget.file.writeAsStringSync(
      jsonEncode({
        'version': 1,
        'requests': [
          {
            'model': 'old',
            'boundUsd': 2.03,
            'heldUsd': 2.03,
            'state': 'reserved',
          },
        ],
      }),
    );
    final reopened = DiscussionBudget(budget.file);
    reopened.reserve(contextLength: 1000000, maxTokens: 3000, model: 'new');
    expect(reopened.rows.first['heldUsd'], 2.03);
    expect(reopened.heldUsd, closeTo(2.536, 0.00001));
  });

  test(
    'pilot evidence preserves failures, raw answers and exact cost totals',
    () {
      final file = File('test/fixtures/book_chat_discussion_pilot_result.json');
      final result = jsonDecode(file.readAsStringSync()) as Map;
      final protocol = jsonDecode(
        File('test/fixtures/book_chat_discussion_protocol.json')
            .readAsStringSync(),
      ) as Map;
      expect(
        sha256.convert(file.readAsBytesSync()).toString(),
        protocol['developmentPilot']['sha256'],
      );
      final rows = [
        for (final run in result['runs'] as List) ...(run['cases'] as List),
      ];
      expect(rows, hasLength(result['requests'] as int));
      expect(rows, hasLength(8));
      expect(rows.where((r) => r['status'] == 'stopped'), hasLength(2));
      expect(rows.every((r) => (r['raw'] as String).isNotEmpty), isTrue);
      expect(
        rows.fold<double>(
          0,
          (sum, r) => sum + (r['usage']['cost'] as num).toDouble(),
        ),
        closeTo(result['actualCostUsd'] as num, 1e-12),
      );
      expect(result['verdict'], 'revise');
      expect(result['realValidationCasesConsumed'], 0);
      final review = (result['review'] as List).last;
      expect(review['scores']['book_factuality'], 0);
      expect(review['scores']['citation_support'], 0);
    },
  );

  test(
    'revision evidence preserves billing uncertainty and parser failures',
    () {
      final file = File(
        'test/fixtures/book_chat_discussion_revision_result.json',
      );
      final result = jsonDecode(file.readAsStringSync()) as Map;
      final protocol = jsonDecode(
        File('test/fixtures/book_chat_discussion_protocol.json')
            .readAsStringSync(),
      ) as Map;
      expect(
        sha256.convert(file.readAsBytesSync()).toString(),
        protocol['sourceBoundaryRevision']['sha256'],
      );
      final rows = [
        for (final run in result['runs'] as List) ...(run['cases'] as List),
      ];
      final dispatched = rows.where((r) => r['reservation'] != null).toList();
      final known = dispatched.where((r) => r['usage'] != null).toList();
      expect(dispatched, hasLength(result['requests'] as int));
      expect(known, hasLength(result['knownUsageRequests'] as int));
      expect(dispatched.length - known.length, result['unknownUsageRequests']);
      expect(
        known.fold<double>(
          0,
          (sum, r) => sum + (r['usage']['cost'] as num).toDouble(),
        ),
        closeTo(result['knownCostUsd'] as num, 1e-12),
      );
      expect(result['unknownUsageRequests'], 1);
      expect(result['unknownReservedUpperBoundUsd'], 2.03);
      final rejected = <String>[];
      for (final review in result['review'] as List) {
        final run = (result['runs'] as List).singleWhere(
          (r) => r['startedAt'] == review['runStartedAt'],
        );
        final row = (run['cases'] as List).singleWhere(
          (r) => r['id'] == review['case'] && r['arm'] == review['arm'],
        );
        try {
          parseDiscussionAnswer(row['raw'] as String, {
            for (final s in row['user']['sources'] as List) s['id'] as String,
          });
        } on FormatException {
          rejected.add(review['case'] as String);
        }
      }
      expect(rejected, ['RD08', 'RD09']);
      expect(result['canonicalCases'], hasLength(10));
      expect(result['verdict'], 'revise');
      expect(result['validationModelRuns'], 0);
    },
  );

  test('request-count exhaustion is independent of cheap billing', () {
    for (var i = 0; i < 120; i++) {
      budget.settle(
        budget.reserve(contextLength: 100, maxTokens: 1, model: 'model'),
        {'cost': 0},
      );
    }
    expect(
      () => budget.reserve(contextLength: 100, maxTokens: 1, model: 'model'),
      throwsStateError,
    );
  });

  test('GLM evidence preserves requested priority and unknown billing', () {
    final file = File('test/fixtures/book_chat_discussion_glm_result.json');
    final result = jsonDecode(file.readAsStringSync()) as Map;
    final protocol = jsonDecode(
      File('test/fixtures/book_chat_discussion_protocol.json')
          .readAsStringSync(),
    ) as Map;
    expect(
      sha256.convert(file.readAsBytesSync()).toString(),
      protocol['glmPriorityPilot']['sha256'],
    );
    expect(result['primaryModel'], 'z-ai/glm-5.3-flash');
    expect(result['fallbackModel'], 'qwen/qwen3.8-flash');
    final runs = result['runs'] as List;
    final rows = [for (final run in runs) ...(run['cases'] as List)];
    expect(rows, hasLength(result['requests'] as int));
    final known = rows.where((r) => r['usage'] != null).toList();
    expect(known, hasLength(result['knownUsageRequests'] as int));
    expect(
      known.fold<double>(
        0,
        (sum, r) => sum + (r['usage']['cost'] as num).toDouble(),
      ),
      closeTo(result['knownCostUsd'] as num, 1e-12),
    );
    expect(rows.length - known.length, 1);
    expect(result['unknownReservedUpperBoundUsd'], 0.525888);
    for (final run in runs.skip(1)) {
      expect(run['model'], result['primaryModel']);
      expect(run['reasoning'], {'effort': 'low', 'exclude': true});
      expect((run['cases'] as List).every((r) => r['requests'] == 1), isTrue);
    }
    expect(result['verdict'], 'revise');
    expect(result['validationModelRuns'], 0);
  });

  test(
    'shared SSE transport sends final guarded prompt and captures usage',
    () async {
      final fake = FakeAdapter()
        ..replies.add(
          sse([
            event('{"ok":true}'),
            'data: {"usage":{"cost":0.01}}\n\n',
            'data: [DONE]\n\n',
          ]),
        );
      final client = Dio(BaseOptions(baseUrl: 'https://openrouter.ai/api/v1'));
      final guard = DiscussionAdapter(
        fake,
        budget,
        model: 'model',
        contextLength: 1000000,
      );
      client.httpClientAdapter = guard;
      client.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final body = Map<String, dynamic>.from(options.data as Map);
            body['provider'] = discussionProvider;
            options.data = body;
            handler.next(options);
          },
        ),
      );
      final reply = await evalStream(
        key: 'test',
        model: 'model',
        system: 'System',
        user: 'Exact user payload',
        maxTokens: 3000,
        client: client,
        jsonOutput: true,
      );
      expect(reply.text, '{"ok":true}');
      expect(fake.requests, hasLength(1));
      final body = fake.requests.single.data as Map;
      expect((body['messages'] as List).last['content'], 'Exact user payload');
      expect(body['max_tokens'], 3000);
      expect(budget.rows, hasLength(1));
      budget.settle(guard.reservation!, reply.usage);
      expect(budget.heldUsd, 0.01);
    },
  );

  test(
    'mandatory-reasoning fallback is blocked before a second paid dispatch',
    () async {
      final fake = FakeAdapter()
        ..replies.add(
          sse([
            'Reasoning is mandatory for this endpoint and cannot be disabled.',
          ], 400),
        );
      final client = Dio(BaseOptions(baseUrl: 'https://openrouter.ai/api/v1'));
      client.httpClientAdapter = DiscussionAdapter(
        fake,
        budget,
        model: 'model',
        contextLength: 1000000,
      );
      client.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final body = Map<String, dynamic>.from(options.data as Map)
              ..['provider'] = discussionProvider;
            options.data = body;
            handler.next(options);
          },
        ),
      );
      await expectLater(
        evalStream(
          key: 'test',
          model: 'model',
          system: 'System',
          user: 'User',
          client: client,
          jsonOutput: true,
        ),
        throwsA(anything),
      );
      expect(fake.requests, hasLength(1));
      expect(budget.rows, hasLength(1));
    },
  );

  test(
    'unsafe routes and missing price caps never reach the network',
    () async {
      final fake = FakeAdapter();
      final guard = DiscussionAdapter(
        fake,
        budget,
        model: 'model',
        contextLength: 1000000,
      );
      for (final path in [
        'https://example.com/api/v1/chat/completions',
        'https://openrouter.ai/api/v1/embeddings',
        'https://openrouter.ai/api/v1/chat/completions',
      ]) {
        expect(
          () => guard.fetch(
            RequestOptions(
              path: path,
              method: 'POST',
              data: {'model': 'model', 'messages': [], 'max_tokens': 800},
            ),
            null,
            null,
          ),
          throwsStateError,
        );
      }
      expect(fake.requests, isEmpty);
      expect(budget.rows, isEmpty);
    },
  );
}
