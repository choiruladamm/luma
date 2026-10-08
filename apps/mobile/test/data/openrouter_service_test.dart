import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/services/openrouter_service.dart';
import 'package:luma/domain/breakdown_prompt.dart';
import 'package:luma/domain/models/ai_reply.dart';

/// Answers each request with the next queued reply; records what was sent.
class FakeAdapter implements HttpClientAdapter {
  final replies = <Object>[]; // ResponseBody, or DioExceptionType to throw
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final next = replies.removeAt(0);
    if (next is DioExceptionType) {
      throw DioException(requestOptions: options, type: next);
    }
    return next as ResponseBody;
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody json(Object body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

/// SSE body delivered in [chunks] (cut anywhere, even mid-line).
ResponseBody sse(List<String> chunks, [int status = 200]) => ResponseBody(
  Stream.fromIterable([for (final c in chunks) utf8.encode(c)]),
  status,
  headers: {
    Headers.contentTypeHeader: ['text/event-stream'],
  },
);

String event(String content) =>
    'data: ${jsonEncode({
      'choices': [
        {
          'delta': {'content': content},
        },
      ],
    })}\n\n';

ResponseBody answer(String content) => json({
  'choices': [
    {
      'message': {'role': 'assistant', 'content': content},
    },
  ],
});

void main() {
  late FakeAdapter adapter;
  late OpenRouterService service;

  setUp(() {
    adapter = FakeAdapter();
    service = OpenRouterService(
      Dio(BaseOptions(baseUrl: 'https://openrouter.ai/api/v1'))
        ..httpClientAdapter = adapter,
    );
  });

  Future<AiReply> explain({String? key = 'sk-or-v1-x'}) => service.explain(
    apiKey: key,
    model: 'z-ai/glm-5.3-flash',
    context: ['Before.'],
    target: ['One.', 'Two.'],
  );

  Matcher fails(AiError error, {int? status}) => throwsA(
    isA<AiException>()
        .having((e) => e.error, 'error', error)
        .having((e) => e.status, 'status', status),
  );

  test('sends model, key, prompt, reasoning off; reads the reply', () async {
    adapter.replies.add(
      answer(
        '```json\n{"translations": ["Satu.", "Dua."], "meaning": "M."}\n```',
      ),
    );
    final r = await explain();
    expect(r.translations, ['Satu.', 'Dua.']);
    expect(r.meaning, 'M.');

    final req = adapter.requests.single;
    expect(req.path, '/chat/completions');
    expect(req.headers['Authorization'], 'Bearer sk-or-v1-x');
    final body = req.data as Map<String, Object?>;
    expect(body['model'], 'z-ai/glm-5.3-flash');
    expect(body['reasoning'], {'enabled': false});
    final messages = body['messages'] as List;
    expect((messages[0] as Map)['role'], 'system');
    expect(
      (messages[1] as Map)['content'],
      'KONTEKS (paragraf sebelumnya):\nBefore.\n\nTARGET:\n[1] One.\n[2] Two.',
    );
  });

  test('a model that cannot turn reasoning off gets the minimum', () async {
    adapter.replies
      ..add(
        json({
          'error': {
            'message':
                'Reasoning is mandatory for this endpoint and cannot be '
                'disabled.',
            'code': 400,
          },
        }, 400),
      )
      ..add(answer('{"translations": ["Satu.", "Dua."], "meaning": "M."}'));
    expect((await explain()).translations, hasLength(2));
    final sent = [
      for (final r in adapter.requests) (r.data as Map)['reasoning'],
    ];
    expect(sent, [
      {'enabled': false},
      {'effort': 'minimal', 'exclude': true},
    ]);
  });

  test('other 400s are not retried', () async {
    adapter.replies.add(json({'error': 'bad model'}, 400));
    await expectLater(explain(), fails(AiError.http, status: 400));
    expect(adapter.requests, hasLength(1));
  });

  test('no API key: nothing is sent', () async {
    await expectLater(explain(key: null), fails(AiError.noApiKey));
    await expectLater(explain(key: ''), fails(AiError.noApiKey));
    expect(adapter.requests, isEmpty);
  });

  test('wrong count is retried once, then succeeds', () async {
    adapter.replies
      ..add(answer('{"translations": ["Satu."], "meaning": "M."}'))
      ..add(answer('{"translations": ["Satu.", "Dua."], "meaning": "M."}'));
    expect((await explain()).translations, hasLength(2));
    expect(adapter.requests, hasLength(2));
  });

  test('invalid twice gives up', () async {
    adapter.replies
      ..add(answer('Maaf.'))
      ..add(answer('Maaf lagi.'));
    await expectLater(explain(), fails(AiError.invalidResponse));
    expect(adapter.requests, hasLength(2));
  });

  test('a reply without content is invalid', () async {
    adapter.replies
      ..add(json({'choices': []}))
      ..add(json({'choices': []}));
    await expectLater(explain(), fails(AiError.invalidResponse));
  });

  test('HTTP errors keep their status, no retry', () async {
    adapter.replies.add(json({'error': 'no credits'}, 402));
    await expectLater(explain(), fails(AiError.http, status: 402));
    expect(adapter.requests, hasLength(1));
  });

  test('timeouts and connection errors', () async {
    adapter.replies.add(DioExceptionType.receiveTimeout);
    await expectLater(explain(), fails(AiError.timeout));
    adapter.replies.add(DioExceptionType.connectionError);
    await expectLater(explain(), fails(AiError.network));
  });

  test('checkKey: accepted, rejected, or a real failure', () async {
    adapter.replies.add(
      json({
        'data': {'label': 'x'},
      }),
    );
    expect(await service.checkKey('sk'), isTrue);
    expect(adapter.requests.single.path, '/key');

    adapter.replies.add(json({'error': 'nope'}, 401));
    expect(await service.checkKey('sk'), isFalse);

    adapter.replies.add(DioExceptionType.connectionError);
    await expectLater(service.checkKey('sk'), fails(AiError.network));
  });

  group('SseDecoder', () {
    test('lines cut at chunk boundaries come out whole', () {
      final d = SseDecoder();
      expect(d.add('data: {"a"'), isEmpty);
      expect(d.add(':1}\n\ndata: [DO'), ['{"a":1}']);
      expect(d.add('NE]\n'), ['[DONE]']);
    });

    test('comments and other fields are skipped', () {
      final d = SseDecoder();
      expect(d.add(': OPENROUTER PROCESSING\n\nevent: x\ndata: 1\n'), ['1']);
    });
  });

  group('explainStream', () {
    Stream<String> stream({String? key = 'sk-or-v1-x'}) =>
        service.explainStream(
          apiKey: key,
          model: 'z-ai/glm-5.3-flash',
          book: (
            title: 'Meditations',
            author: 'Marcus Aurelius',
            chapter: 'II',
          ),
          context: ['Before.'],
          target: ['One.', 'Two.'],
        );

    test('yields the deltas until [DONE], asks for sections', () async {
      final whole =
          '${event('[T1]\nSa')}: OPENROUTER PROCESSING\n\n'
          '${event('tu.\n[T2]\nDua.')}${event('\n[MAKNA]\nM.')}'
          'data: [DONE]\n\n';
      // Split into awkward pieces, including inside a UTF-8 sequence.
      final bytes = utf8.encode(whole);
      adapter.replies.add(
        ResponseBody(
          Stream.fromIterable([
            for (var i = 0; i < bytes.length; i += 7)
              Uint8List.fromList(
                bytes.sublist(i, (i + 7).clamp(0, bytes.length)),
              ),
          ]),
          200,
        ),
      );
      final parts = await stream().toList();
      expect(parts.join(), '[T1]\nSatu.\n[T2]\nDua.\n[MAKNA]\nM.');

      final body = adapter.requests.single.data as Map<String, Object?>;
      expect(body['stream'], isTrue);
      expect(body.containsKey('response_format'), isFalse);
      expect(body['reasoning'], {'enabled': false});
      final system = ((body['messages'] as List)[0] as Map)['content'];
      expect(system, contains('[MAKNA]'));
      final user = ((body['messages'] as List)[1] as Map)['content'] as String;
      expect(user, startsWith('BUKU: Meditations, Marcus Aurelius\nBAB: II\n'));
    });

    test('non-ASCII split across chunks survives', () async {
      final bytes = utf8.encode('${event('“Halo”')}data: [DONE]\n');
      final cut = bytes.indexOf(0xE2) + 1; // inside the 3-byte quote
      adapter.replies.add(
        ResponseBody(
          Stream.fromIterable([
            Uint8List.fromList(bytes.sublist(0, cut)),
            Uint8List.fromList(bytes.sublist(cut)),
          ]),
          200,
        ),
      );
      expect((await stream().toList()).join(), '“Halo”');
    });

    test('closed before [DONE] is a network failure', () async {
      adapter.replies.add(sse([event('[T1]\nSa')]));
      final got = <String>[];
      await expectLater(stream().forEach(got.add), fails(AiError.network));
      expect(got, ['[T1]\nSa']);
    });

    test('an error event mid-stream keeps its code', () async {
      adapter.replies.add(
        sse([
          event('[T1]'),
          'data: {"error": {"code": 502, "message": "provider died"}}\n\n',
        ]),
      );
      await expectLater(
        stream().drain<void>(),
        fails(AiError.http, status: 502),
      );
    });

    test('mandatory reasoning is retried with the minimum', () async {
      adapter.replies
        ..add(
          sse([
            '{"error": {"message": "Reasoning is mandatory for this '
                'endpoint and cannot be disabled.", "code": 400}}',
          ], 400),
        )
        ..add(sse([event('[T1]\nA\n[T2]\nB\n[MAKNA]\nM'), 'data: [DONE]\n']));
      expect(await stream().toList(), hasLength(1));
      expect(
        [for (final r in adapter.requests) (r.data as Map)['reasoning']],
        [
          {'enabled': false},
          {'effort': 'minimal', 'exclude': true},
        ],
      );
    });

    test('HTTP errors read the streamed body; no key sends nothing', () async {
      adapter.replies.add(sse(['{"error": "no credits"}'], 402));
      await expectLater(
        stream().drain<void>(),
        throwsA(
          isA<AiException>()
              .having((e) => e.status, 'status', 402)
              .having((e) => e.detail, 'detail', contains('no credits')),
        ),
      );
      await expectLater(
        stream(key: null).drain<void>(),
        fails(AiError.noApiKey),
      );
      expect(adapter.requests, hasLength(1));
    });
  });

  test('breakdownStream: Bedahin prompts on the same stream path', () async {
    const input = BreakdownInput(
      book: (title: 'The Enchiridion', author: 'Epictetus', chapter: 'V'),
      chapters: ['I', 'V'],
      chapter: 2,
      original: ['Men are disturbed.'],
      translations: ['Manusia terganggu.'],
      meaning: 'M.',
    );
    Stream<String> stream({String? key = 'sk-or-v1-x'}) =>
        service.breakdownStream(
          apiKey: key,
          model: 'z-ai/glm-5.3-flash',
          input: input,
        );

    adapter.replies
      ..add(
        sse([
          '{"error": {"message": "Reasoning is mandatory for this '
              'endpoint and cannot be disabled.", "code": 400}}',
        ], 400),
      )
      ..add(sse([event('[BAGIAN K1-K1]\nJudul: A'), 'data: [DONE]\n']));
    expect((await stream().toList()).join(), '[BAGIAN K1-K1]\nJudul: A');
    final body = adapter.requests.last.data as Map<String, Object?>;
    final messages = body['messages'] as List;
    expect((messages[0] as Map)['content'], breakdownSystemPrompt);
    expect((messages[1] as Map)['content'], breakdownUserPrompt(input));
    expect(body['reasoning'], {'effort': 'minimal', 'exclude': true});

    await expectLater(stream(key: null).drain<void>(), fails(AiError.noApiKey));
    expect(adapter.requests, hasLength(2));
  });
}
