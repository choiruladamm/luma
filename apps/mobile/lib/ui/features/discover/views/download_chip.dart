import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/sheet.dart';
import '../view_models/download_queue_view_model.dart';

/// Chip "Ngunduh N buku · 43%" 12 di atas bar (board Komponen · NavBar).
/// Ilang kalau gak ada yang jalan / antri. Tap = sheet Unduhan (#174; sementara
/// daftar polos).
class DownloadChip extends ConsumerWidget {
  const DownloadChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(downloadQueueProvider);
    final active = items.where((i) => !i.finished).toList();
    if (active.isEmpty) return const SizedBox.shrink();
    final running = active
        .where((i) => i.status != DownloadStatus.queued)
        .firstOrNull;
    final progress = (running?.progress ?? 0).clamp(0.0, 1.0);
    final c = context.stabilo;
    final b = Theme.of(context).brightness;
    final text = 'Ngunduh ${active.length} buku · ${(progress * 100).round()}%';
    return Semantics(
      button: true,
      label: 'Status unduhan, $text',
      child: GestureDetector(
        onTap: () => showAppSheet<void>(
          context,
          builder: (_) => const _DownloadsSheet(),
        ),
        child: Container(
          height: Layout.navChip,
          padding: const EdgeInsets.only(left: 8, right: 14),
          decoration: BoxDecoration(
            color: c.sheet,
            borderRadius: BorderRadius.circular(Layout.navChip / 2),
            border: Border.all(color: c.outline, width: Layout.outline),
            boxShadow: Elevation.capsule(c, b),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 10,
            children: [
              SizedBox.square(
                dimension: Layout.navChipRing,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 4,
                  strokeCap: StrokeCap.round,
                  color: c.ink,
                  backgroundColor: c.track,
                ),
              ),
              ExcludeSemantics(
                child: Text(
                  text,
                  style: StabiloType.label.copyWith(fontSize: 13.5),
                ),
              ),
              AppIcon(
                HugeIcons.strokeRoundedArrowUp01,
                size: 14,
                color: c.ink2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadsSheet extends ConsumerWidget {
  const _DownloadsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(downloadQueueProvider);
    final c = context.stabilo;
    return SheetFrame(
      title: 'Unduhan',
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s2),
            child: Text(
              '${item.book.title} · ${item.label}',
              style: StabiloType.body.copyWith(color: c.ink),
            ),
          ),
      ],
    );
  }
}

extension DownloadItemLabels on DownloadItem {
  String get label => switch (status) {
    DownloadStatus.queued => 'Antri',
    DownloadStatus.downloading =>
      'Lagi diunduh · ${(progress.clamp(0.0, 1.0) * 100).round()}%',
    DownloadStatus.importing => 'Nyusun buku…',
    DownloadStatus.done => 'Udah masuk rak',
    DownloadStatus.duplicate => 'Udah ada di rak',
    DownloadStatus.failed => 'Gagal, koneksinya putus',
  };
}
