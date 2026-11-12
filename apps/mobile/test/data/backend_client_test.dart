import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/services/backend_client.dart';

import '../support/backend_fakes.dart';

void main() {
  late FakeAdapter adapter;
  late List<Duration> sleeps;
  late BackendClient client;

  setUp(() {
    adapter = FakeAdapter();
    sleeps = [];
    client = BackendClient(
      baseUrl: 'https://luma.test',
      dio: Dio()..httpClientAdapter = adapter,
      sleep: (d) async => sleeps.add(d),
    );
  });

  group('backendBaseUrl', () {
    test('dev flavor goes to the dev Worker, everything else to prod', () {
      expect(backendBaseUrl('dev', override: ''), backendUrls['dev']);
      expect(backendBaseUrl('prod', override: ''), backendUrls['prod']);
      expect(backendBaseUrl(null, override: ''), backendUrls['prod']);
    });

    test('BACKEND_URL override wins', () {
      expect(
        backendBaseUrl('dev', override: 'http://10.0.0.5:8787'),
        'http://10.0.0.5:8787',
      );
    });
  });

  group('health', () {
    test('parses the contract response', () async {
      final fixture = contract('health');
      adapter.queue.add(fromContract(fixture));

      final health = await client.health();

      expect(health.status, 'ok');
      expect(health.env, 'dev');
      final req = fixture['request']! as Map<String, Object?>;
      expect(adapter.requests.single.method, req['method']);
      expect(adapter.requests.single.uri.path, req['path']);
    });
  });

  group('retry policy', () {
    test(
      'kill switch 503 with Retry-After is not retried (contract)',
      () async {
        adapter.queue.add(fromContract(contract('error-service-disabled')));

        final e = await client.health().then<Object?>(
          (_) => null,
          onError: (Object e) => e,
        );

        expect(
          e,
          isA<BackendException>()
              .having((e) => e.code, 'code', 'SERVICE_DISABLED')
              .having((e) => e.statusCode, 'status', 503)
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(hours: 1),
              ),
        );
        expect(adapter.requests, hasLength(1));
        expect(sleeps, isEmpty);
      },
    );

    test('429 is not retried and carries Retry-After (contract)', () async {
      adapter.queue.add(fromContract(contract('error-rate-limited')));

      final e = await client.health().then<Object?>(
        (_) => null,
        onError: (Object e) => e,
      );

      expect(
        e,
        isA<BackendException>()
            .having((e) => e.code, 'code', 'RATE_LIMITED')
            .having(
              (e) => e.retryAfter,
              'retryAfter',
              const Duration(seconds: 60),
            ),
      );
      expect(adapter.requests, hasLength(1));
    });

    test('4xx is not retried', () async {
      adapter.queue.add(
        json(400, {
          'error': {'code': 'BAD_REQUEST', 'message': 'nope'},
        }),
      );

      await expectLater(client.health(), throwsA(isA<BackendException>()));
      expect(adapter.requests, hasLength(1));
    });

    test(
      '5xx without Retry-After retries with backoff, max 3 attempts',
      () async {
        for (var i = 0; i < 3; i++) {
          adapter.queue.add(
            json(500, {
              'error': {'code': 'INTERNAL_ERROR', 'message': 'x'},
            }),
          );
        }

        await expectLater(
          client.health(),
          throwsA(
            isA<BackendException>().having(
              (e) => e.code,
              'code',
              'INTERNAL_ERROR',
            ),
          ),
        );
        expect(adapter.requests, hasLength(backendMaxAttempts));
        expect(sleeps, [
          const Duration(milliseconds: 500),
          const Duration(seconds: 1),
        ]);
      },
    );

    test('network failure retries, then succeeds', () async {
      adapter.queue
        ..add(DioExceptionType.connectionError)
        ..add(DioExceptionType.receiveTimeout)
        ..add(json(200, {'status': 'ok', 'env': 'dev'}));

      final health = await client.health();

      expect(health.status, 'ok');
      expect(adapter.requests, hasLength(3));
    });

    test('network failure on every attempt surfaces NETWORK', () async {
      adapter.queue.addAll(List.filled(3, DioExceptionType.connectionTimeout));

      await expectLater(
        client.health(),
        throwsA(
          isA<BackendException>()
              .having((e) => e.code, 'code', 'NETWORK')
              .having((e) => e.statusCode, 'status', isNull),
        ),
      );
    });

    test('non-JSON error body falls back to UNKNOWN', () async {
      adapter.queue.add(
        ResponseBody.fromString(
          '<html>bad gateway</html>',
          502,
          headers: {
            'retry-after': ['30'],
          },
        ),
      );

      await expectLater(
        client.health(),
        throwsA(
          isA<BackendException>()
              .having((e) => e.code, 'code', 'UNKNOWN')
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(seconds: 30),
              ),
        ),
      );
      expect(adapter.requests, hasLength(1));
    });
  });
}
