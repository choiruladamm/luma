import 'package:luma/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/sheet.dart';
import '../../../core/widgets/toast.dart';
import '../../shell/views/app_shell.dart';
import '../view_models/backup_view_model.dart';
import 'backup_sheet.dart';

/// Shows the "Lagi ngebungkus backup" sheet & its result toast on the topmost
/// screen. Mounted in Settings & Rak (reminder banner), so a backup can start
/// from anywhere.
class BackupListener extends ConsumerStatefulWidget {
  const BackupListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<BackupListener> createState() => _BackupListenerState();
}

class _BackupListenerState extends ConsumerState<BackupListener> {
  /// The progress sheet was opened from this screen; closed from here too.
  bool _open = false;

  void _onBackup(BackupState? prev, BackupState next) {
    if (next is! BackupRunning && _open) {
      _open = false;
      Navigator.of(context, rootNavigator: true).pop();
    }
    // Rak and Settings both live in the tab shell: only the visible tab (or the
    // topmost screen) handles it.
    if (!_open &&
        (!(ModalRoute.of(context)?.isCurrent ?? true) ||
            !AppShell.isVisible(context))) {
      return;
    }
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
          context.l10n.backupBackupCompleteAllSafe,
          subtitle:
              '${fileSize(b.size, locale: context.l10n.localeName)} · ${b.name}',
          leading: ToastTile(
            icon: AppIcons.check,
            bg: c.accent,
            fg: c.onAccent,
          ),
        );
      case BackupFailed(:final storageFull):
        backup.dismiss();
        showToast(
          context,
          context.l10n.backupBackupFailed,
          subtitle: storageFull
              ? context.l10n.backupCloudIsFull
              : context.l10n.backupTryAgainInAMoment,
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
