import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/import_repository.dart';
import 'package:luma/data/services/book_source.dart';
import 'package:luma/data/services/file_storage.dart';
import 'package:luma/domain/models/catalog.dart';
import 'package:luma/ui/features/discover/view_models/download_queue_view_model.dart';

/// Sumber palsu: ngasih [bytes] dalam 4 chunk, satu event loop per chunk,
/// biar cancel / antrian keliatan. [fail] = lempar error jaringan.
class FakeSource implements BookSource {
  FakeSource(this.bytes, {this.fail = false});

  final Uint8List bytes;
  final bool fail;
  final started = <String>[];

  @override
  String get id => 'fake';
  @override
  String get name => 'Fake';

  @override
  Future<Uint8List> download(
    CatalogBook book, {
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    started.add(book.externalId);
    for (var i = 1; i <= 4; i++) {
      await Future<void>.delayed(Duration.zero);
      if (isCancelled?.call() ?? false) {
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(),
          reason: 'test',
        );
      }
      if (fail) {
        throw DioException.connectionError(
          requestOptions: RequestOptions(),
          reason: 'test',
        );
      }
      onProgress?.call(i / 4);
    }
    return bytes;
  }

  @override
  Future<CatalogPage> search(String query, {int page = 1}) =>
      throw UnimplementedError();
  @override
  Future<CatalogBookDetail> fetchDetail(String externalId) =>
      throw UnimplementedError();
}

CatalogBook book(String id, [String title = 'Book']) => CatalogBook(
  sourceId: 'fake',
  externalId: id,
  title: title,
  authors: const [],
  coverUrl: '',
  downloadUrl: '',
);

void main() {
  final epub = File('test/fixtures/enchiridion.epub').readAsBytesSync();
  late AppDatabase db;
  late Directory root;
  late FakeSource source;
  ProviderContainer? container;

  Future<void> setUpWith(FakeSource s) async {
    source = s;
    container?.dispose();
    container = ProviderContainer(
      overrides: [
        bookSourcesProvider.overrideWithValue([source]),
        importRepositoryProvider.overrideWithValue(
          ImportRepository(db, FileStorage(root)),
        ),
      ],
    );
  }

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    root = await Directory.systemTemp.createTemp('luma_dl_');
    await FileStorage(root).ensureDirs();
    await setUpWith(FakeSource(epub));
  });
  tearDown(() async {
    container?.dispose();
    await db.close();
    await root.delete(recursive: true);
  });

  Future<List<DownloadItem>> settle() async {
    while (container!.read(downloadQueueProvider).any((i) => !i.finished)) {
      await Future<void>.delayed(Duration.zero);
    }
    return container!.read(downloadQueueProvider);
  }

  test('download → import: book lands in the DB with its identity', () async {
    final states = <List<DownloadItem>>[];
    container!.listen(downloadQueueProvider, (_, s) => states.add(s));
    container!.read(downloadQueueProvider.notifier).enqueue(book('1', 'E'));
    final items = await settle();
    final item = items.single;
    expect(item.status, DownloadStatus.done);
    expect(item.progress, 1);
    final row = await db.select(db.books).getSingle();
    expect((row.id, row.sourceId, row.externalId), (item.bookId, 'fake', '1'));
    expect(
      states.map((s) => s.single.status).toSet(),
      containsAll([
        DownloadStatus.queued,
        DownloadStatus.downloading,
        DownloadStatus.importing,
        DownloadStatus.done,
      ]),
    );
    expect(states.map((s) => s.single.progress), contains(0.5));
  });

  test('one at a time, in order; same book is not queued twice', () async {
    final queue = container!.read(downloadQueueProvider.notifier);
    queue.enqueue(book('1'));
    queue.enqueue(book('2'));
    queue.enqueue(book('1'));
    expect(container!.read(downloadQueueProvider), hasLength(2));
    await Future<void>.delayed(Duration.zero);
    expect(source.started, ['1'], reason: 'second waits');
    final items = await settle();
    expect(source.started, ['1', '2']);
    expect(items.map((i) => i.status), [
      DownloadStatus.done,
      DownloadStatus.duplicate,
    ]);
    expect(items[1].bookId, items[0].bookId);
    expect(await db.select(db.books).get(), hasLength(1));
  });

  test('cancel: queued disappears, running stops and disappears', () async {
    final queue = container!.read(downloadQueueProvider.notifier);
    queue.enqueue(book('1'));
    queue.enqueue(book('2'));
    queue.cancel('fake/2');
    expect(container!.read(downloadQueueProvider).single.key, 'fake/1');
    await Future<void>.delayed(Duration.zero);
    queue.cancel('fake/1');
    final items = await settle();
    expect(items, isEmpty);
    expect(await db.select(db.books).get(), isEmpty);
    expect(source.started, ['1']);
  });

  test(
    'network error → failed with the exception; dismiss removes it',
    () async {
      await setUpWith(FakeSource(epub, fail: true));
      final queue = container!.read(downloadQueueProvider.notifier);
      queue.enqueue(book('1'));
      final items = await settle();
      expect(items.single.status, DownloadStatus.failed);
      expect(items.single.error, isA<DioException>());
      queue.dismiss('fake/1');
      expect(container!.read(downloadQueueProvider), isEmpty);
      // Enqueue again after failure starts over (and fails again).
      queue.enqueue(book('1'));
      expect(container!.read(downloadQueueProvider).single.finished, isFalse);
      expect((await settle()).single.status, DownloadStatus.failed);
      expect(source.started, ['1', '1']);
    },
  );

  test('bad epub → failed, nothing written', () async {
    await setUpWith(FakeSource(Uint8List.fromList([1, 2, 3])));
    container!.read(downloadQueueProvider.notifier).enqueue(book('1'));
    final items = await settle();
    expect(items.single.status, DownloadStatus.failed);
    expect(await db.select(db.books).get(), isEmpty);
  });
}
