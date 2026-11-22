import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/cloud_backup_repository.dart';
import '../../../../data/repositories/usage_repository.dart';
import '../../auth/view_models/auth_view_model.dart';

/// Daily background work when the app opens (session read) and on every
/// resume, if logged in: the cloud backup (docs/backup.md) and the usage
/// rollup. Their intervals and retries live in
/// [CloudBackupRepository.backupIfDue] and [UsageRepository.sendIfDue]. No
/// polling.
class DailyTrigger extends ConsumerStatefulWidget {
  const DailyTrigger({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DailyTrigger> createState() => _DailyTriggerState();
}

class _DailyTriggerState extends ConsumerState<DailyTrigger> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _run);
    // fireImmediately: auth finished before this widget was mounted (app opened
    // while logged in) also counts as logged in.
    ref.listenManual(authControllerProvider, (prev, next) {
      if (next.value?.status == AuthStatus.signedIn &&
          prev?.value?.status != AuthStatus.signedIn) {
        _run();
      }
    }, fireImmediately: true);
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
    unawaited(ref.read(usageRepositoryProvider).sendIfDue());
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
