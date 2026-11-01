import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/book_repository.dart';
import 'package:luma/data/repositories/reading_progress_repository.dart';
import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/data/services/backup_service.dart';
import 'package:luma/data/services/file_storage.dart';
import 'package:luma/domain/models/book.dart';
import 'package:luma/domain/models/catalog.dart';
import 'package:luma/main.dart';
import 'package:luma/ui/core/widgets/nav_bar.dart';
import 'package:luma/ui/features/bookshelf/view_models/bookshelf_view_model.dart';
import 'package:luma/ui/features/discover/view_models/download_queue_view_model.dart';
import 'package:luma/ui/features/discover/views/discover_view.dart';
import 'package:luma/ui/features/reader/view_models/reader_view_model.dart';
import 'package:luma/ui/features/settings/views/settings_view.dart';

import '../../../fakes.dart';
import '../bookshelf/bookshelf_test.dart' show FakeBooks, StuckBackup;

class FakeQueue extends DownloadQueue {
  void emit(List<DownloadItem> items) => state = items;
}

const book = CatalogBook(
  sourceId: 'fake',
  externalId: '1',
  title: 'Emma',
  authors: [],
  coverUrl: '',
  downloadUrl: '',
);

void main() {
  late StreamController<List<ShelfBook>> shelf;
  late FakeQueue queue;

  setUp(() => shelf = StreamController<List<ShelfBook>>.broadcast());
  tearDown(() => unawaited(shelf.close()));

  Future<void> pump(WidgetTester tester) async {
    queue = FakeQueue();
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            FakeSettings()
              ..lastBackup = (at: DateTime.now(), name: 'x.zip', size: 1),
          ),
          backupServiceProvider.overrideWithValue(StuckBackup()),
          bookRepositoryProvider.overrideWithValue(FakeBooks()),
          fileStorageProvider.overrideWithValue(
            FileStorage(Directory.systemTemp),
          ),
          booksStreamProvider.overrideWith((ref) => shelf.stream),
          readerBookProvider.overrideWith((ref, id) async => null),
          readingProgressRepositoryProvider.overrideWithValue(FakeProgress()),
          downloadQueueProvider.overrideWith(() => queue),
        ],
        child: const LumaApp(),
      ),
    );
    shelf.add(const []);
    await tester.pumpAndSettle();
  }

  testWidgets('tabs switch Rak → Cari buku → Atur and back', (tester) async {
    await pump(tester);
    expect(find.text('Rak buku lo'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Cari buku'));
    await tester.pumpAndSettle();
    expect(find.byType(DiscoverView), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Atur'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsView), findsOneWidget);
    expect(find.bySemanticsLabel('Balik'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Rak'));
    await tester.pumpAndSettle();
    expect(find.text('Rak buku lo'), findsOneWidget);
    expect(find.byType(LumaNavBar), findsOneWidget);
  });

  testWidgets('downloads: badge + chip appear, gone when queue is idle', (
    tester,
  ) async {
    await pump(tester);
    expect(find.textContaining('Ngunduh'), findsNothing);
    queue.emit([
      const DownloadItem(
        book: book,
        status: DownloadStatus.downloading,
        progress: 0.43,
      ),
      const DownloadItem(
        book: CatalogBook(
          sourceId: 'fake',
          externalId: '2',
          title: 'Persuasion',
          authors: [],
          coverUrl: '',
          downloadUrl: '',
        ),
      ),
    ]);
    await tester.pump();
    expect(find.text('Ngunduh 2 buku · 43%'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.text('Ngunduh 2 buku · 43%'));
    await tester.pumpAndSettle();
    expect(find.text('Unduhan'), findsOneWidget);
    expect(find.text('Jalan terus walau lo pindah layar'), findsOneWidget);
    expect(find.text('Lagi diunduh · 43%'), findsOneWidget);
    expect(find.text('Antri, abis Emma'), findsOneWidget);
    expect(find.bySemanticsLabel('Batalin'), findsOneWidget);
    expect(find.bySemanticsLabel('Hapus dari antrian'), findsOneWidget);

    // Hapus yang antri: hilang + toast.
    await tester.tap(find.bySemanticsLabel('Hapus dari antrian'));
    await tester.pump();
    expect(find.text('Unduhan Persuasion dibatalin'), findsOneWidget);
    expect(find.text('Antri, abis Emma'), findsNothing);

    // Selesai: Baca; ditutup → entri selesai dibuang.
    queue.emit([
      const DownloadItem(book: book, status: DownloadStatus.done, bookId: 1),
    ]);
    await tester.pump();
    expect(find.text('Udah masuk rak'), findsOneWidget);
    expect(find.text('Baca'), findsWidgets); // baris sheet + toast
    await tester.tap(find.bySemanticsLabel('Tutup'));
    await tester.pumpAndSettle();
    expect(queue.state, isEmpty);
    queue.emit([
      const DownloadItem(book: book, status: DownloadStatus.downloading),
    ]);
    await tester.pump();

    queue.emit([
      const DownloadItem(book: book, status: DownloadStatus.done, bookId: 1),
    ]);
    await tester.pump();
    expect(find.text('2'), findsNothing);
  });

  testWidgets('keyboard up hides the bar', (tester) async {
    await pump(tester);
    expect(find.byType(LumaNavBar), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(find.byType(LumaNavBar), findsNothing);
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(find.byType(LumaNavBar), findsOneWidget);
  });
}
