import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/cloud_backup_repository.dart';
import '../../auth/view_models/auth_view_model.dart';

/// Backup cloud otomatis (docs/backup.md): saat app kebuka (sesi kebaca) dan
/// tiap resume, kalau login. Jeda 24 jam & coba lagi ada di
/// [CloudBackupRepository.backupIfDue]. Tanpa polling.
class CloudBackupTrigger extends ConsumerStatefulWidget {
  const CloudBackupTrigger({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<CloudBackupTrigger> createState() => _CloudBackupTriggerState();
}

class _CloudBackupTriggerState extends ConsumerState<CloudBackupTrigger> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _run);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _run() {
    final auth = ref.read(authControllerProvider).value;
    if (auth?.status != AuthStatus.signedIn) return;
    unawaited(ref.read(cloudBackupRepositoryProvider).backupIfDue());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (prev, next) {
      if (next.value?.status == AuthStatus.signedIn &&
          prev?.value?.status != AuthStatus.signedIn) {
        _run();
      }
    });
    return widget.child;
  }
}
