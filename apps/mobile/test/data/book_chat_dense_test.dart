import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/book_chat_dense.dart';
import '../support/book_chat_spike.dart';
import 'openrouter_service_test.dart' show FakeAdapter, json;

void main() {
  test(
    'embedding parser orders indices and rejects malformed vectors/model',
    () {
      Map<String, Object> response(List<Object> rows) => {
        'model': embeddingModel,
        'data': rows,
      };
      final a = {
        'index': 0,
        'embedding': [3, 4],
      };
      final b = {
        'index': 1,
        'embedding': [0, 1],
      };
      final v = parseEmbeddings(response([b, a]), 2, 2);
      expect(
        parseEmbeddings(
          {
            'model': 'parasail-bge-m3',
            'provider': 'Parasail',
            'data': [a, b],
          },
          2,
          2,
        ),
        hasLength(2),
      );
      expect(
        () => parseEmbeddings(
          {
            'model': 'parasail-bge-m3',
            'provider': 'other',
            'data': [a, b],
          },
          2,
          2,
        ),
        throwsFormatException,
      );
      expect(v.first[0], closeTo(0.6, 0.00001));
      expect(v.last[1], 1);
      expect(() => normalizedVector([1e-80, 1e-80], 2), throwsFormatException);
      expect(
        parseEmbeddings(
          {
            'model': 'BAAI/bge-m3',
            'data': [a, b],
          },
          2,
          2,
        ),
        hasLength(2),
      );
      for (final bad in [
        response([a, a]),
        response([a]),
        response([
          {
            'index': 2,
            'embedding': [1, 2],
          },
          b,
        ]),
        response([
          {
            'index': 0,
            'embedding': [1],
          },
          b,
        ]),
        response([
          {
            'index': 0,
            'embedding': [0, 0],
          },
          b,
        ]),
        response([
          {
            'index': 0,
            'embedding': [double.nan, 1],
          },
          b,
        ]),
        {
          'model': 'other',
          'data': [a, b],
        },
      ]) {
        expect(() => parseEmbeddings(bad, 2, 2), throwsFormatException);
      }
    },
  );

  test(
    'cache reuses exact model/text and never calls API without opt-in',
    () async {
      final dir = Directory.systemTemp.createTempSync('luma-embedding-test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/cache.jsonl');
      final cache = EmbeddingCache(file);
      final adapter = FakeAdapter()
        ..replies.add(
          json({
            'model': embeddingModel,
            'data': [
              {
                'index': 0,
                'embedding': [1, ...List.filled(1023, 0)],
              },
              {
                'index': 1,
                'embedding': [0, 1, ...List.filled(1022, 0)],
              },
            ],
            'usage': {'prompt_tokens': 2, 'cost': 0.00000002},
          }),
        );
      final dio = Dio(BaseOptions(baseUrl: 'https://openrouter.ai/api/v1'))
        ..httpClientAdapter = adapter;
      addTearDown(() => dio.close());
      await expectLater(
        cache.fill(['one'], live: false, apiKey: null, dio: dio),
        throwsStateError,
      );
      expect(adapter.requests, isEmpty);
      await cache.fill(
        ['one', 'two', 'one'],
        live: true,
        apiKey: 'test',
        dio: dio,
      );
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.data['input'], ['one', 'two']);
      expect(adapter.requests.single.data['encoding_format'], 'float');
      final replay = EmbeddingCache(file);
      await replay.fill(['two', 'one'], live: false, apiKey: null, dio: dio);
      expect(replay.newRequests, 0);
      expect(replay.vector('one')[0], 1);
      expect(
        () => EmbeddingCache(
          file,
          model: 'qwen/qwen3-embedding-8b',
          dimensions: 4096,
        ),
        throwsFormatException,
      );
      await expectLater(
        replay.fill(['changed'], live: false, apiKey: null, dio: dio),
        throwsStateError,
      );
    },
  );

  test(
    'dense ranking filters book/revision before lookup and fusion deduplicates',
    () {
      final dir = Directory.systemTemp.createTempSync('luma-dense-test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final cache = EmbeddingCache(File('${dir.path}/unused'));
      Passage passage(String id, String book, int revision, String text) => (
        id: id,
        book: book,
        revision: revision,
        chapter: '1',
        from: 0,
        to: 0,
        text: text,
        hash: textHash(text),
      );
      final a = passage('a', 'owned', 1, 'first');
      final b = passage('b', 'owned', 1, 'second');
      cache.vectors[cache.key(a.text)] = Float32List.fromList([1, 0]);
      cache.vectors[cache.key(b.text)] = Float32List.fromList([0, 1]);
      final found = denseSearch(
        [
          a,
          b,
          passage('foreign', 'other', 1, 'uncached'),
          passage('stale', 'owned', 2, 'uncached'),
        ],
        cache,
        Float32List.fromList([1, 0]),
        'owned',
      );
      expect(found, [a, b]);
      expect(
        denseSearch(
          [a, b],
          cache,
          Float32List.fromList([1, 0]),
          'owned',
          quoteId: 'b',
        ).first,
        b,
      );
      expect(fuseRanks([a, a, b], [b, a]).map((p) => p.id).toSet(), {'a', 'b'});
      expect(fuseRanks([a, b], [a, b], quoteId: 'b').first, b);
    },
  );
}
