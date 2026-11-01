import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../../routing/router.dart';
import '../../../core/widgets/sheet.dart';
import '../../../core/widgets/toast.dart';
import 'catalog_cover.dart';
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

/// Sheet Unduhan (board 14): baris lagi diunduh (Batalin), antri ("Antri,
/// abis Emma" + Hapus dari antrian), gagal (Coba lagi), selesai (Baca).
/// Yang selesai / gagal di-`dismiss` pas sheet ditutup.
class _DownloadsSheet extends ConsumerStatefulWidget {
  const _DownloadsSheet();

  @override
  ConsumerState<_DownloadsSheet> createState() => _DownloadsSheetState();
}

class _DownloadsSheetState extends ConsumerState<_DownloadsSheet> {
  // `ref` gak boleh dipakai di dispose: simpen notifier + daftar terakhir.
  late final DownloadQueue _queue;
  var _last = const <DownloadItem>[];

  @override
  void initState() {
    super.initState();
    _queue = ref.read(downloadQueueProvider.notifier);
  }

  @override
  void dispose() {
    // Provider gak boleh diubah pas tree lagi dibongkar: tunda satu microtask.
    final finished = [
      for (final i in _last)
        if (i.finished) i.key,
    ];
    if (finished.isNotEmpty) {
      scheduleMicrotask(() => finished.forEach(_queue.dismiss));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _last = ref.watch(downloadQueueProvider);
    final c = context.stabilo;
    final queue = _queue;
    String? before(int i) =>
        items.take(i).where((x) => !x.finished).lastOrNull?.book.title;
    return SheetFrame(
      title: 'Unduhan',
      children: [
        Transform.translate(
          offset: const Offset(0, -Space.s3),
          child: Text(
            'Jalan terus walau lo pindah layar',
            style: StabiloType.caption.copyWith(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: c.ink2,
            ),
          ),
        ),
        if (items.isEmpty)
          Text(
            'Gak ada yang lagi diunduh.',
            style: StabiloType.body.copyWith(color: c.ink2),
          ),
        for (final (i, item) in items.indexed) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: c.track),
          _DownloadRow(
            item: item,
            queuedAfter: item.status == DownloadStatus.queued
                ? before(i)
                : null,
            onCancel: () {
              queue.cancel(item.key);
              if (!item.finished) {
                showToast(context, 'Unduhan ${item.book.title} dibatalin');
              }
            },
            onRetry: () => queue.enqueue(item.book),
            onRead: () =>
                ref.read(routerProvider).push(Routes.reader(item.bookId!)),
          ),
        ],
      ],
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({
    required this.item,
    required this.queuedAfter,
    required this.onCancel,
    required this.onRetry,
    required this.onRead,
  });

  final DownloadItem item;
  final String? queuedAfter;
  final VoidCallback onCancel, onRetry, onRead;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final status = queuedAfter == null
        ? item.label
        : 'Antri, abis $queuedAfter';
    final failed = item.status == DownloadStatus.failed;
    final trailing = switch (item.status) {
      DownloadStatus.queued => CircleButton(
        semanticLabel: 'Hapus dari antrian',
        icon: AppIcons.close,
        size: 40,
        onPressed: onCancel,
      ),
      DownloadStatus.downloading || DownloadStatus.importing => CircleButton(
        semanticLabel: 'Batalin',
        icon: AppIcons.close,
        size: 40,
        onPressed: onCancel,
      ),
      DownloadStatus.failed => _Pill(label: 'Coba lagi', onTap: onRetry),
      DownloadStatus.done ||
      DownloadStatus.duplicate => _Pill(label: 'Baca', onTap: onRead),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s2),
      child: Row(
        spacing: Space.s3,
        children: [
          CatalogCover(book: item.book, width: 44),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: [
                Text(
                  item.book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: StabiloType.label.copyWith(height: 1.2),
                ),
                Text(
                  status,
                  style: StabiloType.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: failed ? c.ink : c.ink2,
                  ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.muted,
            borderRadius: BorderRadius.circular(Radii.full),
          ),
          child: Text(label, style: StabiloType.label.copyWith(fontSize: 14)),
        ),
      ),
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
