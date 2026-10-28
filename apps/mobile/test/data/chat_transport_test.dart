import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/services/openrouter_service.dart';
import 'package:luma/domain/models/ai_reply.dart';
import 'package:luma/domain/models/book_chat.dart';

import 'openrouter_service_test.dart' show FakeAdapter, sse, json, event;

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
  Stream<String> send({String? key = 'key', CancelToken? cancel}) =>
      service.chatStream(
        apiKey: key,
        model: 'chosen',
        system: 'system',
        user: 'follow up',
        history: [
          {'role': 'user', 'content': 'q'},
          {'role': 'assistant', 'content': 'a'},
        ],
        cancel: cancel,
      );
  Matcher fails(AiError error, [int? status]) => throwsA(
    isA<AiException>()
        .having((e) => e.error, 'error', error)
        .having((e) => e.status, 'status', status),
  );

  test(
    'multi-turn JSON with split SSE/Unicode uses existing bounded transport',
    () async {
      final wire = ': comment\n\n${event('🌿 Indonesia')}data: [DONE]\n\n';
      adapter.replies.add(
        ResponseBody(
          Stream.fromIterable(
            utf8.encode(wire).map((b) => Uint8List.fromList([b])),
          ),
          200,
        ),
      );
      expect(await send().join(), '🌿 Indonesia');
      final r = adapter.requests.single;
      expect(r.headers['Authorization'], 'Bearer key');
      final data = r.data as Map;
      expect(data['model'], 'chosen');
      expect(data['messages'], [
        {'role': 'system', 'content': 'system'},
        {'role': 'user', 'content': 'q'},
        {'role': 'assistant', 'content': 'a'},
        {'role': 'user', 'content': 'follow up'},
      ]);
      expect(data['stream'], true);
      expect(data['max_tokens'], 800);
      expect(data['response_format'], {'type': 'json_object'});
      expect(data['reasoning'], {'enabled': false});
    },
  );

  test('mandatory reasoning fallback happens once before content', () async {
    adapter.replies.addAll([
      json({'error': 'Reasoning is mandatory'}, 400),
      sse([event('{}'), 'data: [DONE]\n\n']),
    ]);
    expect(await send().join(), '{}');
    expect(adapter.requests, hasLength(2));
    final a = adapter.requests[0].data as Map,
        b = adapter.requests[1].data as Map;
    expect(b['messages'], a['messages']);
    expect(b['max_tokens'], a['max_tokens']);
    expect(b['response_format'], a['response_format']);
    expect(b['reasoning'], {'effort': 'minimal', 'exclude': true});
  });

  for (final status in [401, 403, 402, 429, 500]) {
    test('HTTP $status never auto-retries chat', () async {
      adapter.replies.add(json({'error': 'rejected'}, status));
      await expectLater(send().join(), fails(AiError.http, status));
      expect(adapter.requests, hasLength(1));
    });
  }
  test('missing DONE and embedded errors fail, never replay content', () async {
    adapter.replies.add(sse([event('partial')]));
    await expectLater(send().join(), fails(AiError.network));
    adapter.replies.add(
      sse([
        event('partial'),
        'data: {"error":{"code":429}}\n\ndata: [DONE]\n\n',
      ]),
    );
    await expectLater(send().join(), fails(AiError.http, 429));
    expect(adapter.requests, hasLength(2));
  });
  test('no key and cancelled request send nothing', () async {
    await expectLater(send(key: null).join(), fails(AiError.noApiKey));
    final cancel = CancelToken()..cancel();
    await expectLater(send(cancel: cancel).join(), fails(AiError.network));
    expect(adapter.requests, isEmpty);
  });
  test('cancel after first delta closes stream with no retry', () async {
    final cancel = CancelToken();
    adapter.replies.add(
      sse([event('partial'), event('more'), 'data: [DONE]\n\n']),
    );
    final seen = <String>[];
    try {
      await for (final delta in send(cancel: cancel)) {
        seen.add(delta);
        cancel.cancel();
      }
    } on AiException catch (e) {
      expect(e.error, AiError.network);
    }
    expect(seen, ['partial']);
    expect(adapter.requests, hasLength(1));
  });
  test(
    'embedding trust boundary rejects unknown model/dimensions without retry',
    () async {
      adapter.replies.add(json({'model': 'other', 'data': []}));
      await expectLater(
        service.embeddings(
          apiKey: 'key',
          model: ChatEmbeddingModel.qwen8b,
          input: ['text'],
        ),
        fails(AiError.invalidResponse),
      );
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.path, '/embeddings');
      expect((adapter.requests.single.data as Map)['encoding_format'], 'float');
    },
  );
}
