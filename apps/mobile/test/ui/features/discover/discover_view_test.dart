import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/catalog_repository.dart';
import 'package:luma/data/services/book_source.dart';
import 'package:luma/data/services/catalog_sync_service.dart';
import 'package:luma/domain/catalog/catalog_row.dart';
import 'package:luma/domain/models/catalog.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/core/widgets/tag.dart';
import 'package:luma/ui/features/discover/view_models/discover_view_model.dart';
import 'package:luma/ui/features/discover/view_models/download_queue_view_model.dart';
import 'package:luma/ui/features/discover/views/discover_view.dart';

/// Populer nunggu [popular] diselesaikan; cari langsung dari [catalog].
/// Completer dibikin pas dipakai (di dalam zone FakeAsync test widget),
/// bukan di setUp: kalau gak, microtask-nya jatuh ke event loop asli.
class FakeSource implements BookSource {
  Completer<CatalogPage>? _popular;
  Completer<CatalogPage> get popular => _popular ??= Completer();
  set popular(Completer<CatalogPage> c) => _popular = c;
  Completer<CatalogBookDetail>? _detail;
  Completer<CatalogBookDetail> get detail => _detail ??= Completer();
  set detail(Completer<CatalogBookDetail> c) => _detail = c;
  final detailRequests = <String>[];
  final catalog = <CatalogBook>[];
  final queries = <String>[];
  Object? searchError;

  var sourceId = 'fake';

  @override
  String get id => sourceId;
  @override
  String get name => 'Fake';

  @override
  Future<CatalogPage> search(String query, {int page = 1}) async {
    queries.add('$query@$page');
    if (query.trim().isEmpty) return popular.future;
    if (searchError case final e?) throw e;
    final hits = catalog
        .where((b) => b.title.toLowerCase().contains(query.toLowerCase()))
        .toList();
    final start = (page - 1) * CatalogRepository.pageSize;
    final items = hits.skip(start).take(CatalogRepository.pageSize).toList();
    return CatalogPage(
      items: items,
      hasMore: start + items.length < hits.length,
      total: hits.length,
    );
  }

  @override
  Future<CatalogBookDetail> fetchDetail(String externalId) {
    detailRequests.add(externalId);
    return detail.future;
  }

  /// Gak pernah selesai: status antrian digerakin dari test.
  @override
  Future<Uint8List> download(
    CatalogBook book, {
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) => Completer<Uint8List>().future;
}

class FakeSync extends CatalogSyncController {
  final calls = <bool>[];
  @override
  Future<void> sync({bool force = false}) async => calls.add(force);
  void emit(CatalogSyncState s) => state = s;
}

class FakeQueue extends DownloadQueue {
  void emit(List<DownloadItem> items) => state = items;
}

CatalogBook book(int id, String title, [String author = 'Austen, Jane']) =>
    CatalogBook(
      sourceId: 'fake',
      externalId: '$id',
      title: title,
      authors: [CatalogAuthor(author, birth: 1775, death: 1817)],
      coverUrl: '',
      downloadUrl: '',
    );

void main() {
  late FakeSource source;
  late FakeSync sync;
  late FakeQueue queue;
  late StreamController<CatalogStats> stats;
  var shelfIds = <String>{};

  setUp(() {
    source = FakeSource();
    sync = FakeSync();
    queue = FakeQueue();
    stats = StreamController<CatalogStats>.broadcast();
    shelfIds = {};
  });
  tearDown(() {
    unawaited(stats.close());
  });

  Future<void> pump(
    WidgetTester tester, {
    int count = 62000,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookSourcesProvider.overrideWithValue([source]),
          catalogSyncProvider.overrideWith(() => sync),
          catalogStatsProvider.overrideWith((ref) => stats.stream),
          downloadQueueProvider.overrideWith(() => queue),
          shelfExternalIdsProvider.overrideWith(
            (ref, id) => Stream.value(shelfIds),
          ),
        ],
        child: MaterialApp(
          theme: stabiloTheme(brightness),
          home: const DiscoverView(),
        ),
      ),
    );
    stats.add((count: count, syncedAt: DateTime(2026), lastModified: null));
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  /// `pump()` tanpa durasi cuma ngejalanin microtask; `Future(...)` dan
  /// jawaban async butuh timer 0 → dua frame berdurasi nol.
  Future<void> tick(WidgetTester tester) async {
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(DiscoverView)));

  final popular = [
    book(1342, 'Pride and Prejudice'),
    book(84, 'Frankenstein', 'Shelley, Mary'),
    book(2701, 'Moby Dick', 'Melville, Herman'),
  ];

  testWidgets('top chart: skeleton → #1 card + rank row; sync() once', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('LAGI RAME'), findsOneWidget);
    expect(find.text('#1 lagi rame'), findsNothing);
    source.popular.complete(CatalogPage(items: popular, hasMore: true));
    await tick(tester);
    expect(find.text('#1 lagi rame'), findsOneWidget);
    expect(find.text('Pride and Prejudice'), findsOneWidget);
    expect(find.text('Jane Austen'), findsWidgets); // kartu + cover default
    expect(find.text('Frankenstein'), findsWidgets);
    expect(find.text('Moby Dick'), findsWidgets);
    expect(find.text('Sherlock Holmes'), findsOneWidget); // preset chip
    expect(sync.calls, [false]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('slow after 5 s shows the notice, then the list', (tester) async {
    await pump(tester);
    await tester.pump(const Duration(seconds: 6));
    await tick(tester);
    expect(find.text('Katalognya lagi lemot nih'), findsOneWidget);
    source.popular.complete(CatalogPage(items: popular, hasMore: true));
    await tick(tester);
    expect(find.text('Katalognya lagi lemot nih'), findsNothing);
    expect(find.text('#1 lagi rame'), findsOneWidget);
  });

  testWidgets('dead catalog: notice + Coba lagi refetches', (tester) async {
    await pump(tester);
    source.popular.completeError(
      DioException(
        requestOptions: RequestOptions(),
        response: Response(requestOptions: RequestOptions(), statusCode: 503),
      ),
    );
    await tick(tester);
    expect(find.text('Katalog lagi gak bisa dihubungin'), findsOneWidget);
    source.popular = Completer();
    await tester.tap(find.text('Coba lagi'));
    await tick(tester);
    expect(source.queries.where((q) => q == '@1'), hasLength(2));
    source.popular.complete(CatalogPage(items: popular, hasMore: false));
    await tick(tester);
    expect(find.text('#1 lagi rame'), findsOneWidget);
  });

  testWidgets('offline: Lo lagi offline + Buka rak', (tester) async {
    await pump(tester);
    source.popular.completeError(
      DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.connectionError,
        error: const SocketException('x'),
      ),
    );
    await tick(tester);
    expect(find.text('Lo lagi offline'), findsOneWidget);
    expect(find.text('Buka rak'), findsOneWidget);
    expect(find.text('LAGI RAME'), findsNothing);
  });

  testWidgets('typing searches locally: Paling cocok, rows, badges, count', (
    tester,
  ) async {
    source.catalog.addAll([
      book(1342, 'Pride and Prejudice'),
      book(158, 'Emma'),
      book(161, 'Sense and Sensibility'),
      book(105, 'Persuasion'),
    ]);
    shelfIds = {'1342'};
    await pump(tester);
    containerOf(tester).read(downloadQueueProvider); // bangun notifier-nya
    queue.emit([
      DownloadItem(
        book: book(105, 'Persuasion'),
        status: DownloadStatus.downloading,
        progress: 0.43,
      ),
      DownloadItem(book: book(161, 'Sense and Sensibility')),
    ]);
    await tick(tester);
    await tester.enterText(find.byType(TextField), 'e');
    await tick(tester);
    expect(find.text('HASIL BUAT “E”'), findsOneWidget);
    expect(find.text('4 hasil · urut paling cocok'), findsOneWidget);
    expect(find.text('Paling cocok'), findsOneWidget);
    expect(find.text('Udah di rak'), findsOneWidget);
    expect(find.text('Lagi diunduh · 43%'), findsOneWidget);
    expect(find.text('Antri'), findsOneWidget);
    expect(find.byType(Tag), findsNWidgets(3));
    expect(source.queries, ['@1', 'e@1']);
    expect(find.textContaining('Ngambil'), findsNothing);

    // Clear → back to Top chart.
    await tester.tap(find.bySemanticsLabel('Hapus kata cari'));
    await tick(tester);
    expect(find.text('LAGI RAME'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no hits: Gak nemu', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'mobi dik');
    await tick(tester);
    expect(find.text('Gak nemu “mobi dik”'), findsOneWidget);
  });

  testWidgets('paging: footer, scroll loads page 2, failure offers retry', (
    tester,
  ) async {
    for (var i = 1; i <= 30; i++) {
      source.catalog.add(book(i, 'Book $i'));
    }
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'book');
    await tick(tester);
    expect(find.text('30 hasil · urut paling cocok'), findsOneWidget);

    // Mentok bawah = ngambil halaman 2; kali ini gagal.
    source.searchError = Exception('boom');
    await tester.drag(find.byType(ListView).last, const Offset(0, -3000));
    await tick(tester);
    expect(find.text('Gagal ngambil. Coba lagi'), findsOneWidget);
    expect(source.queries.last, 'book@2');

    source.searchError = null;
    await tester.tap(find.text('Gagal ngambil. Coba lagi'));
    await tick(tester);
    expect(source.queries.where((q) => q == 'book@2'), hasLength(2));
    await tester.drag(find.byType(ListView).last, const Offset(0, -3000));
    await tick(tester);
    expect(find.text('Book 30'), findsWidgets);
    expect(find.text('Ngambil 25 lagi…'), findsNothing);
    expect(find.text('Gagal ngambil. Coba lagi'), findsNothing);
  });

  testWidgets('preset chip fills the field and searches', (tester) async {
    source.catalog.add(book(1, 'The Adventures of Sherlock Holmes'));
    await pump(tester);
    source.popular.complete(CatalogPage(items: popular, hasMore: false));
    await tick(tester);
    await tester.tap(find.text('Dickens'));
    await tick(tester);
    expect(find.text('Gak nemu “Dickens”'), findsOneWidget);
    expect(find.text('Dickens'), findsOneWidget); // isi kolom cari
  });

  testWidgets('no catalog yet: setup runs, progress, failure → Coba lagi', (
    tester,
  ) async {
    await pump(tester, count: 0);
    expect(find.text('Nyiapin katalog buku…'), findsOneWidget);
    expect(sync.calls, [false, false]); // auto (VM) + setup (view)
    sync.emit(const CatalogSyncDownloading(0.43));
    await tick(tester);
    expect(find.text('Nyiapin katalog buku… 43%'), findsOneWidget);
    sync.emit(const CatalogSyncFailed('x'));
    await tick(tester);
    expect(find.text('Katalog lagi gak bisa dihubungin'), findsOneWidget);
    await tester.tap(find.text('Coba lagi'));
    expect(sync.calls.last, isTrue);
    // Catalog arrives: top chart takes over.
    stats.add((count: 5, syncedAt: DateTime(2026), lastModified: null));
    await tick(tester);
    expect(find.text('LAGI RAME'), findsOneWidget);
  });
}
