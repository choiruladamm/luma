import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/services/notification_service.dart';
import '../../../../routing/router.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/widgets/toast.dart';
import '../view_models/download_queue_view_model.dart';

/// Kabar download selesai / gagal, dari mana pun user lagi berada (board 15 /
/// 16): toast "Emma udah masuk rak" + Buka (di layar baca) / Baca. App di
/// latar (#175): notifikasi lokal dengan kalimat yang sama, tap = buka buku.
/// Dipasang di `builder` MaterialApp (di bawah ScaffoldMessenger, di atas
/// router), jadi navigasinya lewat [routerProvider], bukan context.
class DownloadToasts extends ConsumerStatefulWidget {
  const DownloadToasts({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DownloadToasts> createState() => _DownloadToastsState();
}

class _DownloadToastsState extends ConsumerState<DownloadToasts> {
  late final AppLifecycleListener _lifecycle;
  var _background = false;
  var _asked = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (s) => _background =
          s == AppLifecycleState.paused || s == AppLifecycleState.hidden,
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _open(int bookId) =>
      ref.read(routerProvider).push(Routes.reader(bookId));

  @override
  Widget build(BuildContext context) {
    ref.listen(downloadQueueProvider, (previous, next) {
      final before = {for (final i in previous ?? const []) i.key: i.status};
      final notifications = ref.read(notificationServiceProvider);
      for (final item in next) {
        if (before[item.key] == item.status) continue;
        // Download pertama mulai = saat yang pas minta izin notifikasi.
        if (item.status == DownloadStatus.downloading && !_asked) {
          _asked = true;
          notifications
              .init((payload) => _open(int.parse(payload)))
              .then((_) => notifications.requestPermission())
              .ignore();
        }
        if (!item.finished) continue;
        final title = item.book.title;
        final message = switch (item.status) {
          DownloadStatus.done => '$title udah masuk rak',
          DownloadStatus.duplicate => '$title udah ada di rak',
          _ => 'Gagal ngunduh $title',
        };
        final bookId = item.bookId;
        if (_background) {
          notifications
              .show(
                id: item.key.hashCode,
                title: message,
                body: bookId == null ? null : 'Tap buat mulai baca',
                payload: bookId?.toString(),
              )
              .ignore();
          continue;
        }
        final router = ref.read(routerProvider);
        final reading = router.routeInformationProvider.value.uri.path
            .startsWith('/reader/');
        showToast(
          context,
          message,
          actionLabel: bookId == null ? null : (reading ? 'Buka' : 'Baca'),
          duration: Motion.toastBaca,
          onAction: bookId == null ? null : () => _open(bookId),
        );
      }
    });
    return widget.child;
  }
}
