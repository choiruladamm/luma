import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:luma/data/services/notification_service.dart';
import 'package:luma/domain/models/catalog.dart';
import 'package:luma/routing/router.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/features/discover/view_models/download_queue_view_model.dart';
import 'package:luma/ui/features/discover/views/download_toasts.dart';

class FakeQueue extends DownloadQueue {
  void emit(List<DownloadItem> items) => state = items;
}

class FakeNotifications extends Fake implements NotificationService {
  final shown = <(String, String?)>[];
  var permissionAsked = 0;
  void Function(String payload)? onTap;

  @override
  Future<void> init(void Function(String payload) onTap) async =>
      this.onTap = onTap;

  @override
  Future<bool> requestPermission() async {
    permissionAsked++;
    return true;
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    String? body,
    String? payload,
  }) async => shown.add((title, payload));
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
  late FakeNotifications notifications;
  late GoRouter router;

  Future<void> pump(WidgetTester tester) async {
    queue = FakeQueue();
    notifications = FakeNotifications();
    router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SizedBox()),
        GoRoute(path: '/reader/:id', builder: (_, _) => const SizedBox()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          downloadQueueProvider.overrideWith(() => queue),
          routerProvider.overrideWith((ref) => router),
          notificationServiceProvider.overrideWithValue(notifications),
        ],
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
    // Download pertama = minta izin notifikasi sekali.
    expect(notifications.permissionAsked, 1);

    queue.emit([
      const DownloadItem(book: book, status: DownloadStatus.done, bookId: 7),
    ]);
    await tester.pump();
    expect(find.text('Enchiridion udah masuk rak'), findsOneWidget);
    expect(find.text('Baca'), findsOneWidget);
    expect(notifications.shown, isEmpty);

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
        status: DownloadStatus.downloading,
      ),
    ]);
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(notifications.permissionAsked, 1);
  });

  testWidgets('failed → Gagal ngunduh', (tester) async {
    await pump(tester);
    queue.emit([const DownloadItem(book: book, status: DownloadStatus.failed)]);
    await tester.pump();
    expect(find.text('Gagal ngunduh Enchiridion'), findsOneWidget);
    expect(find.text('Baca'), findsNothing);
  });

  testWidgets('app in background → local notification, not a toast', (
    tester,
  ) async {
    await pump(tester);
    queue.emit([
      const DownloadItem(book: book, status: DownloadStatus.downloading),
    ]);
    await tester.pump();
    // Urutan sah: resumed → inactive → hidden → paused.
    for (final s in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    queue.emit([
      const DownloadItem(book: book, status: DownloadStatus.done, bookId: 7),
    ]);
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
    expect(notifications.shown, [('Enchiridion udah masuk rak', '7')]);

    // Tap notifikasi = buka bukunya.
    notifications.onTap!('7');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/reader/7');

    // Resumed again: back to toasts.
    for (final s in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    queue.emit([const DownloadItem(book: book, status: DownloadStatus.failed)]);
    await tester.pump();
    expect(find.text('Gagal ngunduh Enchiridion'), findsOneWidget);
    expect(notifications.shown, hasLength(1));
  });
}
