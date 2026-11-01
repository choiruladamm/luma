import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/models/catalog.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/features/discover/view_models/download_queue_view_model.dart';
import 'package:luma/ui/features/discover/views/download_toasts.dart';

class FakeQueue extends DownloadQueue {
  void emit(List<DownloadItem> items) => state = items;
}

const book = CatalogBook(
  sourceId: 'fake',
  externalId: '1',
  title: 'Enchiridion',
  authors: [],
  coverUrl: '',
  downloadUrl: '',
);

void main() {
  late FakeQueue queue;

  Future<void> pump(WidgetTester tester) async {
    queue = FakeQueue();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [downloadQueueProvider.overrideWith(() => queue)],
        child: MaterialApp(
          theme: stabiloTheme(Brightness.light),
          builder: (context, child) => DownloadToasts(child: child!),
          home: const Scaffold(body: SizedBox()),
        ),
      ),
    );
  }

  testWidgets('done → toast with Baca; progress changes stay quiet', (
    tester,
  ) async {
    await pump(tester);
    queue.emit([
      const DownloadItem(book: book, status: DownloadStatus.downloading),
    ]);
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);

    queue.emit([
      const DownloadItem(book: book, status: DownloadStatus.done, bookId: 7),
    ]);
    await tester.pump();
    expect(find.text('Sip, udah masuk rak!'), findsOneWidget);
    expect(find.text('Enchiridion'), findsOneWidget);
    expect(find.text('Baca'), findsOneWidget);

    // Same finished state again (e.g. another item changes): no second toast.
    queue.emit([
      const DownloadItem(book: book, status: DownloadStatus.done, bookId: 7),
      const DownloadItem(
        book: CatalogBook(
          sourceId: 'fake',
          externalId: '2',
          title: 'Other',
          authors: [],
          coverUrl: '',
          downloadUrl: '',
        ),
        status: DownloadStatus.queued,
      ),
    ]);
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('failed → Gagal ngunduh', (tester) async {
    await pump(tester);
    queue.emit([const DownloadItem(book: book, status: DownloadStatus.failed)]);
    await tester.pump();
    expect(find.text('Gagal ngunduh'), findsOneWidget);
    expect(find.text('Baca'), findsNothing);
  });
}
