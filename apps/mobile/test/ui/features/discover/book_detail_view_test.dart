import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:luma/data/services/book_source.dart';
import 'package:luma/data/services/catalog_sync_service.dart';
import 'package:luma/domain/models/book.dart';
import 'package:luma/domain/models/catalog.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/features/bookshelf/view_models/bookshelf_view_model.dart';
import 'package:luma/ui/features/discover/view_models/book_detail_view_model.dart';
import 'package:luma/ui/features/discover/view_models/discover_view_model.dart';
import 'package:luma/ui/features/discover/view_models/download_queue_view_model.dart';
import 'package:luma/ui/features/discover/views/book_detail_view.dart';

import 'discover_view_test.dart' show FakeQueue, FakeSource, FakeSync, book;

const emma = CatalogBookDetail(
  summary:
      'Emma Woodhouse is clever, rich, and quite sure she knows best. Bored '
      'in the quiet village of Highbury, she sets herself up as matchmaker '
      'for her friends, misreading nearly every heart around her, including '
      'her own. A sharp, funny novel about pride, blindness, and growing up.',
  subjects: ['Young women -- Fiction', 'Love stories'],
  bookshelves: ['Best Books Ever', 'Category: Novels'],
  fileSize: 1200000,
  issued: '1994-08-01T00:00:00+00:00',
);

void main() {
  late FakeSource source;
  late FakeQueue queue;
  late GoRouter router;
  int? shelfId;
  var shelfBooks = <ShelfBook>[];

  setUp(() {
    source = FakeSource();
    queue = FakeQueue();
    shelfId = null;
    shelfBooks = [];
  });

  Future<void> tick(WidgetTester tester) async {
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  Future<void> pump(
    WidgetTester tester,
    CatalogBook b, {
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/detail',
          builder: (_, _) => BookDetailView(book: b),
        ),
        GoRoute(
          path: '/reader/:id',
          builder: (_, s) =>
              Scaffold(body: Text('reader ${s.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookSourcesProvider.overrideWithValue([source]),
          catalogSyncProvider.overrideWith(FakeSync.new),
          downloadQueueProvider.overrideWith(() => queue),
          shelfExternalIdsProvider.overrideWith(
            (ref, id) => Stream.value(const {}),
          ),
          shelfBookIdProvider.overrideWith((ref, b) async => shelfId),
          authorBookCountProvider.overrideWith((ref, a) async => 6),
          booksStreamProvider.overrideWith((ref) => Stream.value(shelfBooks)),
        ],
        child: MaterialApp.router(
          theme: stabiloTheme(brightness),
          routerConfig: router,
        ),
      ),
    );
    // Di app detail selalu di-push dari tab Cari buku: ada yang bisa di-pop.
    router.push('/detail');
    await tester.pumpAndSettle();
    await tick(tester);
  }

  final b = book(158, 'Emma');

  testWidgets('header from the catalog row; detail fills in', (tester) async {
    await pump(tester, b);
    expect(find.text('Detail buku'), findsOneWidget);
    expect(find.text('Emma'), findsWidgets);
    expect(find.text('1775–1817'), findsOneWidget);
    expect(find.text('Ambil buku'), findsOneWidget);
    expect(find.text('Gratis, langsung masuk Rak buku lo'), findsOneWidget);
    expect(source.detailRequests, ['158']);

    source.detail.complete(emma);
    await tick(tester);
    expect(find.text('1994'), findsOneWidget);
    expect(find.text('1,1 MB'), findsNWidgets(2)); // kotak + Info file
    expect(find.text('Inggris'), findsOneWidget);
    expect(find.text('Baca selengkapnya'), findsOneWidget);
    expect(find.text('Young women'), findsOneWidget); // " -- Fiction" dropped
    expect(find.text('Novels'), findsOneWidget); // "Category: " dropped
    expect(find.text('1775–1817 · 6 buku lain di katalog'), findsOneWidget);
    expect(find.text('Public domain di AS'), findsOneWidget);
    expect(find.text('#158'), findsOneWidget);

    await tester.tap(find.text('Baca selengkapnya'));
    await tester.pump();
    expect(find.text('Baca selengkapnya'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no summary → fallback copy; slow and dead states', (
    tester,
  ) async {
    await pump(tester, b);
    await tester.pump(const Duration(seconds: 6));
    await tick(tester);
    expect(find.text('Katalognya lagi lemot nih'), findsOneWidget);
    source.detail.completeError(Exception('503'));
    await tick(tester);
    expect(find.text('Katalog lagi gak bisa dihubungin'), findsOneWidget);
    source.detail = Completer();
    await tester.tap(find.text('Coba lagi'));
    await tick(tester);
    source.detail.complete(const CatalogBookDetail());
    await tick(tester);
    expect(
      find.text('Belum ada sinopsis buat buku ini. Langsung buka bab 1 aja.'),
      findsOneWidget,
    );
    expect(source.detailRequests, ['158', '158']);
  });

  testWidgets('offline detail shows Lo lagi offline', (tester) async {
    await pump(tester, b);
    source.detail.completeError(
      DioException(
        requestOptions: RequestOptions(),
        error: const SocketException('x'),
      ),
    );
    await tick(tester);
    expect(find.text('Lo lagi offline'), findsOneWidget);
  });

  testWidgets('Ambil → progress + Batal → Baca sekarang', (tester) async {
    await pump(tester, b);
    await tester.tap(find.text('Ambil buku'));
    await tick(tester);
    // FakeQueue has no source download: drive the state by hand.
    queue.emit([
      DownloadItem(book: b, status: DownloadStatus.downloading, progress: 0.43),
    ]);
    await tester.pump();
    expect(find.text('Lagi diunduh…'), findsOneWidget);
    expect(find.text('43%'), findsOneWidget);
    expect(find.text('Batal'), findsOneWidget);
    expect(
      find.text('Boleh ditinggal, nanti gua kabarin pas udah masuk rak.'),
      findsOneWidget,
    );

    queue.emit([DownloadItem(book: b, status: DownloadStatus.done, bookId: 7)]);
    await tester.pump();
    expect(find.text('Baca sekarang'), findsOneWidget);
    await tester.tap(find.text('Baca sekarang'));
    await tester.pumpAndSettle();
    expect(find.text('reader 7'), findsOneWidget);
  });

  testWidgets('already on the shelf: tag + Lanjut baca with progress', (
    tester,
  ) async {
    shelfId = 3;
    shelfBooks = [
      ShelfBook(
        id: 3,
        title: 'Emma',
        author: 'Jane Austen',
        coverName: null,
        opened: true,
        createdAt: DateTime(2026),
        progress: 0.03,
      ),
    ];
    await pump(tester, b);
    expect(find.text('Udah di rak'), findsOneWidget);
    expect(find.text('Lanjut baca · 3%'), findsOneWidget);
    expect(
      find.text('Udah ada di rak lo, gak perlu diunduh lagi'),
      findsOneWidget,
    );
  });

  testWidgets('failed → pink ribbon + Coba lagi re-enqueues', (tester) async {
    await pump(tester, b);
    queue.emit([DownloadItem(book: b, status: DownloadStatus.failed)]);
    await tester.pump();
    expect(find.text('Gagal ngunduh, koneksinya putus.'), findsOneWidget);
    await tester.tap(find.text('Coba lagi'));
    await tester.pump();
    // enqueue replaces the failed entry and starts over right away.
    expect(queue.state.single.finished, isFalse);
  });

  testWidgets('author row: tap sets the search query and pops', (tester) async {
    await pump(tester, b);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(BookDetailView)),
    );
    final sub = container.listen(discoverProvider, (_, _) {});
    addTearDown(sub.close);
    await tester.pump(Duration.zero); // jumlah buku penulis kebaca
    await tester.tap(find.textContaining('buku lain di katalog'));
    await tester.pumpAndSettle();
    expect(container.read(discoverProvider).query, 'Jane Austen');
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('long title shrinks (dark)', (tester) async {
    await pump(
      tester,
      book(1079, 'The Life and Opinions of Tristram Shandy, Gentleman'),
      brightness: Brightness.dark,
    );
    final title = tester.widget<Text>(
      find.text('The Life and Opinions of Tristram Shandy, Gentleman').first,
    );
    expect(title.style!.fontSize, 21);
    expect(tester.takeException(), isNull);
  });
}
