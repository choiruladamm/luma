import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/book_chat_dense.dart';
import '../support/book_chat_embedding_fallback.dart';
import '../support/book_chat_heldout.dart';
import 'openrouter_service_test.dart' show FakeAdapter, json;

void main() {
  test('fallback eligibility excludes auth/billing/input/cancel/certificate errors', () {
    DioException error(int status) => DioException(
      requestOptions: RequestOptions(),
      type: DioExceptionType.badResponse,
      response: Response(requestOptions: RequestOptions(), statusCode: status),
    );
    for (final s in [404, 408, 429, 500, 502, 503]) {
      expect(isEmbeddingProviderFailure(error(s)), isTrue);
    }
    for (final s in [400, 401, 402, 403, 413]) {
      expect(isEmbeddingProviderFailure(error(s)), isFalse);
    }
    expect(
      isEmbeddingProviderFailure(
        DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.cancel,
        ),
      ),
      isFalse,
    );
    expect(
      isEmbeddingProviderFailure(
        DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.badCertificate,
        ),
      ),
      isFalse,
    );
  });
  test('provider failure rebuilds full corpus with Large, separate vectors and query template', () async {
    final dir = Directory.systemTemp.createTempSync('luma-fallback');
    addTearDown(() => dir.deleteSync(recursive: true));
    final primary = EmbeddingCache(
      File('${dir.path}/qwen'),
      model: heldoutEmbeddingModel,
      dimensions: 4096,
    );
    primary.vectors[primary.key('document one')] = Float32List.fromList([
      1,
      ...List.filled(4095, 0),
    ]);
    final fallback = LargeEmbeddingCache(File('${dir.path}/large'));
    Object reply(int n) => json({
      'model': 'text-embedding-3-large',
      'data': [
        for (var i = 0; i < n; i++)
          {
            'index': i,
            'embedding': [1, ...List.filled(3071, 0)],
          },
      ],
      'usage': {'prompt_tokens': n, 'cost': 0.000001},
    });
    final adapter = FakeAdapter()
      ..replies.addAll([DioExceptionType.receiveTimeout, reply(2), reply(1)]);
    final dio = Dio(BaseOptions(baseUrl: 'https://openrouter.ai/api/v1'))
      ..httpClientAdapter = adapter;
    addTearDown(() => dio.close());
    final result = await fillWithEmbeddingFallback(
      primary: primary,
      fallback: fallback,
      documents: ['document one', 'document two'],
      primaryQueries: ['${heldoutQueryPrefix}question'],
      fallbackQueries: ['question'],
      live: true,
      apiKey: 'test',
      dio: dio,
    );
    expect(result.cache.model, largeEmbeddingModel);
    expect(result.cache.dimensions, 3072);
    expect(result.fallbackReason, isNotNull);
    expect(result.cache.vectors, hasLength(3));
    expect(primary.vectors, hasLength(1));
    expect(adapter.requests[1].data['input'], ['document one', 'document two']);
    expect(adapter.requests.last.data['input'], ['question']);
    expect(primary.key('document one'), isNot(fallback.key('document one')));
    final replay = LargeEmbeddingCache(fallback.file);
    await replay.fill(
      ['document one', 'document two', 'question'],
      live: false,
      apiKey: null,
      dio: dio,
    );
    final before = adapter.requests.length;
    final skipped = await fillWithEmbeddingFallback(
      primary: primary,
      fallback: fallback,
      documents: ['document one', 'document two'],
      primaryQueries: ['${heldoutQueryPrefix}question'],
      fallbackQueries: ['question'],
      live: true,
      apiKey: 'test',
      dio: dio,
      primaryUnavailable: true,
    );
    expect(skipped.fallbackReason, 'recorded_primary_provider_timeouts');
    expect(adapter.requests.length, before);
    expect(replay.newRequests, 0);
    expect(replay.vector('question'), hasLength(3072));
    expect(
      embeddingQueryForModel(
        '${heldoutQueryPrefix}question',
        largeEmbeddingModel,
      ),
      'question',
    );
    expect(
      embeddingQueryForModel(
        '${heldoutQueryPrefix}question',
        heldoutEmbeddingModel,
      ),
      '${heldoutQueryPrefix}question',
    );
  });
  test('unauthorized primary does not call fallback', () async {
    final dir = Directory.systemTemp.createTempSync('luma-fallback-auth');
    addTearDown(() => dir.deleteSync(recursive: true));
    final primary = EmbeddingCache(
      File('${dir.path}/qwen'),
      model: heldoutEmbeddingModel,
      dimensions: 4096,
    );
    final fallback = LargeEmbeddingCache(File('${dir.path}/large'));
    final adapter = FakeAdapter()
      ..replies.add(json({'error': 'unauthorized'}, 401));
    final dio = Dio(BaseOptions(baseUrl: 'https://openrouter.ai/api/v1'))
      ..httpClientAdapter = adapter;
    addTearDown(() => dio.close());
    await expectLater(
      fillWithEmbeddingFallback(
        primary: primary,
        fallback: fallback,
        documents: ['doc'],
        primaryQueries: ['q'],
        fallbackQueries: ['q'],
        live: true,
        apiKey: 'test',
        dio: dio,
      ),
      throwsA(isA<DioException>()),
    );
    expect(adapter.requests, hasLength(1));
    expect(fallback.newRequests, 0);
  });
}
