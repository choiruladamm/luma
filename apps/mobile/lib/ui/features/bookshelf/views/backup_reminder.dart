import 'package:flutter/material.dart';

import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';

/// ReminderBanner di Rak (board 24, Komponen 04). Pink, bukan accent, biar
/// gak rebutan sama kartu lanjut baca & tombol Import.
class BackupReminder extends StatelessWidget {
  const BackupReminder({
    super.key,
    required this.days,
    required this.neverBackedUp,
    required this.onBackup,
    required this.onClose,
  });

  /// Udah berapa hari (dari backup terakhir / buku pertama).
  final int days;
  final bool neverBackedUp;
  final VoidCallback onBackup;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final (title, body) = neverBackedUp
        ? (
            'Belum pernah backup nih',
            'Data lo cuma ada di HP ini doang. Amanin dulu yuk.',
          )
        : days == 6
        ? (
            'Udah 6 hari belum backup nih',
            'Besok jatah install ulang. Amanin data lo dulu yuk.',
          )
        : (
            'Udah $days hari belum backup nih',
            'Amanin data lo dulu yuk, sebelum keburu install ulang.',
          );
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Pengingat backup',
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, Space.s3, 6, Space.s3),
        decoration: BoxDecoration(
          color: c.pink,
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.s3,
          children: [
            Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                color: c.bannerTile,
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Center(
                child: AppIcon(
                  AppIcons.clock,
                  size: Layout.icon,
                  color: c.onPink,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    title,
                    style: StabiloType.label.copyWith(
                      height: 1.25,
                      color: c.onPink,
                    ),
                  ),
                  Text(
                    body,
                    style: StabiloType.caption.copyWith(
                      height: 1.35,
                      fontWeight: FontWeight.w400,
                      color: c.onPink,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Material(
                      color: c.bannerButton,
                      shape: const StadiumBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: onBackup,
                        child: Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.s4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 6,
                            children: [
                              AppIcon(
                                AppIcons.backup,
                                size: 16,
                                color: c.onBannerButton,
                              ),
                              Text(
                                'Backup sekarang',
                                style: StabiloType.label.copyWith(
                                  fontSize: 14,
                                  color: c.onBannerButton,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -6),
              child: Semantics(
                container: true,
                button: true,
                label: 'Tutup pengingat',
                excludeSemantics: true,
                child: InkResponse(
                  onTap: onClose,
                  radius: Layout.touch / 2,
                  child: SizedBox.square(
                    dimension: Layout.touch,
                    child: Center(
                      child: AppIcon(AppIcons.close, size: 18, color: c.onPink),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
