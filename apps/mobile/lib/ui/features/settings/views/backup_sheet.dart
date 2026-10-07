import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/sheet.dart';
import '../view_models/backup_view_model.dart';

/// Lagi ngebungkus backup (board 26). Ditutup dari Pengaturan pas state-nya
/// udah bukan [BackupRunning]; "Batalin" matiin proses zip-nya.
class BackupProgressSheet extends ConsumerWidget {
  const BackupProgressSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.stabilo;
    final state = ref.watch(backupControllerProvider);
    final run = state is BackupRunning ? state : const BackupRunning();
    final m = run.manifest;
    final items = [
      '${thousands(m?.books ?? 0)} buku + progres bacanya',
      '${thousands(m?.aiResults ?? 0)} terjemahan',
      'Pengaturan baca & model AI',
    ];
    return Semantics(
      label: 'Lagi backup',
      child: Padding(
        padding: Layout.sheetPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.s4,
          children: [
            const SheetGrabber(),
            Row(
              spacing: Space.s3,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: c.muted,
                    borderRadius: BorderRadius.circular(Radii.field),
                  ),
                  child: Center(
                    child: AppIcon(AppIcons.backup, size: 22, color: c.ink),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          'Lagi ngebungkus backup...',
                          style: StabiloType.titleSm.copyWith(fontSize: 21),
                        ),
                      ),
                      Text(
                        run.name ?? ' ',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: StabiloType.mono.copyWith(
                          fontSize: 12.5,
                          color: c.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Row(
              spacing: Space.s3,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.full),
                    child: LinearProgressIndicator(
                      value: run.fraction,
                      minHeight: 8,
                      backgroundColor: c.track,
                      color: c.progressFill,
                    ),
                  ),
                ),
                Text(
                  '${(run.fraction * 100).floor()}%',
                  style: StabiloType.caption.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 10,
              children: [
                for (final (i, label) in items.indexed)
                  SheetStep(
                    label: label,
                    done: m != null && run.stage.index > i,
                    current: m != null && run.stage.index == i,
                  ),
              ],
            ),
            Text(
              'Abis ini muncul menu share iOS. Pilih "Simpan ke Files" terus '
              'taruh di iCloud Drive biar aman.',
              style: StabiloType.caption.copyWith(
                fontWeight: FontWeight.w400,
                height: 1.45,
                color: c.ink2,
              ),
            ),
            AppButton.secondary(
              label: 'Batalin',
              onPressed: ref.read(backupControllerProvider.notifier).cancel,
            ),
          ],
        ),
      ),
    );
  }
}

/// Satu baris centang di sheet proses (backup & pulihin): beres = centang,
/// lagi jalan = titik kuning, belum = titik pasir.
class SheetStep extends StatelessWidget {
  const SheetStep({
    super.key,
    required this.label,
    required this.done,
    required this.current,
  });

  final String label;
  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Row(
      spacing: 10,
      children: [
        SizedBox.square(
          dimension: 22,
          child: done
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.muted,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: AppIcon(AppIcons.check, size: 12, color: c.ink),
                  ),
                )
              : Center(
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: current ? c.accent : c.track,
                      shape: BoxShape.circle,
                      border: current
                          ? Border.all(
                              color: c.accentBorder,
                              width: Layout.outline,
                            )
                          : null,
                    ),
                  ),
                ),
        ),
        Expanded(
          child: Text(
            label,
            style: StabiloType.label.copyWith(
              fontWeight: current ? FontWeight.w700 : FontWeight.w500,
              color: done || current ? c.ink : c.ink2,
            ),
          ),
        ),
      ],
    );
  }
}
