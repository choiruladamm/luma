import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../routing/router.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/widgets/toast.dart';
import '../view_models/download_queue_view_model.dart';

/// Toast pas download selesai / gagal, dari mana pun user lagi berada
/// (board 15 / 16): "Emma udah masuk rak" + Buka (di layar baca) / Baca.
/// Dipasang di `builder` MaterialApp (di bawah ScaffoldMessenger, di atas
/// router), jadi navigasinya lewat [routerProvider], bukan context.
class DownloadToasts extends ConsumerWidget {
  const DownloadToasts({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(downloadQueueProvider, (previous, next) {
      final before = {for (final i in previous ?? const []) i.key: i.status};
      for (final item in next) {
        if (!item.finished || before[item.key] == item.status) continue;
        final title = item.book.title;
        final router = ref.read(routerProvider);
        final reading = router.routeInformationProvider.value.uri.path
            .startsWith('/reader/');
        switch (item.status) {
          case DownloadStatus.done:
          case DownloadStatus.duplicate:
            showToast(
              context,
              item.status == DownloadStatus.done
                  ? '$title udah masuk rak'
                  : '$title udah ada di rak',
              actionLabel: reading ? 'Buka' : 'Baca',
              duration: Motion.toastBaca,
              onAction: () => router.push(Routes.reader(item.bookId!)),
            );
          case DownloadStatus.failed:
            showToast(
              context,
              'Gagal ngunduh $title',
              duration: Motion.toastBaca,
            );
          case DownloadStatus.queued:
          case DownloadStatus.downloading:
          case DownloadStatus.importing:
            break;
        }
      }
    });
    return child;
  }
}
