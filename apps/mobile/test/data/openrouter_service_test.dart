import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/services/openrouter_service.dart';
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
}
