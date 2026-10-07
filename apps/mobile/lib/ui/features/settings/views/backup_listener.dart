import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/sheet.dart';
import '../../../core/widgets/toast.dart';
import '../view_models/backup_view_model.dart';
import 'backup_sheet.dart';

/// Nampilin sheet "Lagi ngebungkus backup" & toast hasilnya di layar yang
/// lagi paling atas. Dipasang di Pengaturan & Rak (banner pengingat), jadi
/// backup bisa dimulai dari mana aja.
class BackupListener extends ConsumerStatefulWidget {
  const BackupListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<BackupListener> createState() => _BackupListenerState();
}

class _BackupListenerState extends ConsumerState<BackupListener> {
  /// Sheet progres kebuka dari layar ini; ditutup dari sini juga.
  bool _open = false;

  void _onBackup(BackupState? prev, BackupState next) {
    if (next is! BackupRunning && _open) {
      _open = false;
      Navigator.of(context).pop();
    }
    // Rak ketumpuk Pengaturan: cuma layar paling atas yang ngurus.
    if (!_open && !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final c = context.stabilo;
    final backup = ref.read(backupControllerProvider.notifier);
    switch (next) {
      case BackupRunning() when !_open:
        _open = true;
        showAppSheet<void>(
          context,
          dismissible: false,
          builder: (_) => const BackupProgressSheet(),
        );
      case BackupDone(backup: final b):
        backup.dismiss();
        showToast(
          context,
          'Backup kelar, aman!',
          subtitle: '${fileSize(b.size)} · ${b.name}',
          leading: ToastTile(
            icon: AppIcons.check,
            bg: c.accent,
            fg: c.onAccent,
          ),
        );
      case BackupFailed():
        backup.dismiss();
        showToast(
          context,
          'Yah, backup gagal',
          subtitle: 'Coba lagi bentar ya',
          leading: ToastTile(icon: AppIcons.alert, bg: c.pink, fg: c.onPink),
        );
      default:
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(backupControllerProvider, _onBackup);
    return widget.child;
  }
}
