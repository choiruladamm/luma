import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/catalog_repository.dart';
import 'package:luma/data/services/catalog_sync_service.dart';
import 'package:luma/domain/catalog/catalog_row.dart';

/// Scripted responses, one per request; records every request.
class FakeAdapter implements HttpClientAdapter {
  final queue = <Object>[];
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final next = queue.removeAt(0);
    if (next is ResponseBody) return next;
    if (next is DioExceptionType) {
      throw DioException(requestOptions: options, type: next);
    }
    throw next;
  }

  @override
  void close({bool force = false}) {}
}

final lastModified = 'Sun, 25 Oct 2026 21:41:56 GMT';

ResponseBody ok(List<int> gz) => ResponseBody.fromBytes(
  gz,
  200,
  headers: {
    'content-length': ['${gz.length}'],
    'last-modified': [lastModified],
  },
);

ResponseBody status(int code) => ResponseBody.fromBytes(const [], code);

void main() {
  late AppDatabase db;
  late CatalogRepository repo;
  late FakeAdapter adapter;
  late CatalogSyncService service;
  var now = DateTime(2026, 10, 31, 12);
  final gz = GZipEncoder().encode(
    File('test/fixtures/catalog/pg_catalog_sample.csv').readAsBytesSync(),
  );

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    repo = CatalogRepository(db);
    adapter = FakeAdapter();
    service = CatalogSyncService(
      repo,
      dio: Dio()..httpClientAdapter = adapter,
      retryDelay: Duration.zero,
      now: () => now,
    );
  });
  tearDown(() => db.close());

  Future<void> seedOld() async {
    await repo.replaceAll(const [CatalogRow(id: 1, title: 'Old', authors: [])]);
    await repo.saveMeta(
      syncedAt: DateTime(2026, 10, 1),
      lastModified: lastModified,
      count: 1,
    );
  }

  test('200: downloads, parses, replaces, saves meta', () async {
    adapter.queue.add(ok(gz));
    final progress = <double>[];
    var importing = false;
    final result = await service.sync(
      onProgress: progress.add,
      onImporting: () => importing = true,
    );
    expect(result, CatalogSyncResult.updated);
    expect(importing, isTrue);
    expect(progress.last, 1.0);
    expect(adapter.requests.single.uri.toString(), CatalogSyncService.url);
    // Empty table: never send If-Modified-Since.
    expect(adapter.requests.single.headers['If-Modified-Since'], isNull);
    expect(await repo.stats(), (
      count: 22,
      syncedAt: now,
      lastModified: lastModified,
    ));
    expect((await repo.search('pride')).single.id, 1342);
  });

  test('skips when fresh, force goes to the server anyway', () async {
    await seedOld();
    now = DateTime(2026, 10, 5);
    expect(await service.sync(), CatalogSyncResult.skipped);
    expect(adapter.requests, isEmpty);

    adapter.queue.add(status(304));
    expect(await service.sync(force: true), CatalogSyncResult.notModified);
    expect(adapter.requests.single.headers['If-Modified-Since'], lastModified);
    final stats = await repo.stats();
    expect(stats.syncedAt, now);
    expect(stats.count, 1);
    expect((await repo.search('old')).single.id, 1);
  });

  test('stale after 7 days → asks the server', () async {
    await seedOld();
    now = DateTime(2026, 10, 9);
    adapter.queue.add(status(304));
    expect(await service.sync(), CatalogSyncResult.notModified);
  });

  test('503 twice then 200 succeeds; 503 three times fails', () async {
    adapter.queue.addAll([status(503), status(429), ok(gz)]);
    expect(await service.sync(), CatalogSyncResult.updated);
    expect(adapter.requests.length, 3);

    adapter.requests.clear();
    adapter.queue.addAll([status(503), status(503), status(503)]);
    await expectLater(
      service.sync(force: true),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'status',
          503,
        ),
      ),
    );
    expect(adapter.requests.length, 3);
    // Previous catalog untouched.
    expect((await repo.search('pride')).single.id, 1342);
  });

  test('404 is not retried', () async {
    adapter.queue.add(status(404));
    await expectLater(service.sync(), throwsA(isA<DioException>()));
    expect(adapter.requests.length, 1);
  });

  test('timeout leaves the old table and meta alone', () async {
    await seedOld();
    adapter.queue.add(DioExceptionType.connectionTimeout);
    await expectLater(
      service.sync(force: true),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.connectionTimeout,
        ),
      ),
    );
    expect((await repo.stats()).syncedAt, DateTime(2026, 10, 1));
    expect((await repo.search('old')).single.id, 1);
  });

  test('broken gzip: old table intact, temp dir removed', () async {
    await seedOld();
    final before = Directory.systemTemp
        .listSync()
        .where((e) => e.path.contains('luma-catalog-'))
        .length;
    adapter.queue.add(ok([1, 2, 3, 4]));
    await expectLater(service.sync(force: true), throwsA(anything));
    expect((await repo.search('old')).single.id, 1);
    expect((await repo.stats()).count, 1);
    final after = Directory.systemTemp
        .listSync()
        .where((e) => e.path.contains('luma-catalog-'))
        .length;
    expect(after, before);
  });

  test('cancel mid-download throws cancel, nothing written', () async {
    await seedOld();
    final body = StreamController<Uint8List>();
    adapter.queue.add(
      ResponseBody(
        body.stream,
        200,
        headers: {
          'content-length': ['1000'],
        },
      ),
    );
    final cancel = CancelToken();
    final run = service.sync(force: true, cancel: cancel);
    body.add(Uint8List(100));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    cancel.cancel();
    await expectLater(
      run,
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
    await body.close();
    expect((await repo.search('old')).single.id, 1);
  });

  group('CatalogSyncController', () {
    late ProviderContainer container;
    setUp(() {
      container = ProviderContainer(
        overrides: [catalogSyncServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
    });

    test('walks checking → downloading → importing → idle', () async {
      adapter.queue.add(ok(gz));
      final seen = <Type>[];
      container.listen(
        catalogSyncProvider,
        (_, s) => seen.add(s.runtimeType),
        fireImmediately: true,
      );
      await container.read(catalogSyncProvider.notifier).sync();
      expect(seen.first, CatalogSyncIdle);
      expect(seen, contains(CatalogSyncChecking));
      expect(seen, contains(CatalogSyncDownloading));
      expect(seen, contains(CatalogSyncImporting));
      expect(seen.last, CatalogSyncIdle);
      expect((await repo.stats()).count, 22);
    });

    test('304 → upToDate until dismissed', () async {
      await seedOld();
      adapter.queue.add(status(304));
      final n = container.read(catalogSyncProvider.notifier);
      await n.sync(force: true);
      expect(container.read(catalogSyncProvider), isA<CatalogSyncUpToDate>());
      n.dismiss();
      expect(container.read(catalogSyncProvider), isA<CatalogSyncIdle>());
    });

    test('failure → failed with reason; sync again works', () async {
      adapter.queue.addAll([status(404), ok(gz)]);
      final n = container.read(catalogSyncProvider.notifier);
      await n.sync();
      expect(
        container.read(catalogSyncProvider),
        isA<CatalogSyncFailed>().having((s) => s.reason, 'reason', 'HTTP 404'),
      );
      await n.sync();
      expect(container.read(catalogSyncProvider), isA<CatalogSyncIdle>());
      expect((await repo.stats()).count, 22);
    });

    test('second sync while running is a no-op; cancel → idle', () async {
      await seedOld();
      final body = StreamController<Uint8List>();
      adapter.queue.add(
        ResponseBody(
          body.stream,
          200,
          headers: {
            'content-length': ['1000'],
          },
        ),
      );
      final n = container.read(catalogSyncProvider.notifier);
      final first = n.sync(force: true);
      body.add(Uint8List(100));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        container.read(catalogSyncProvider),
        isA<CatalogSyncDownloading>(),
      );
      await n.sync(force: true); // no-op, returns at once
      expect(adapter.requests.length, 1);
      n.cancel();
      await first;
      await body.close();
      expect(container.read(catalogSyncProvider), isA<CatalogSyncIdle>());
      expect((await repo.search('old')).single.id, 1);
    });
  });
}
