import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/sync_repository.dart';
import '../../auth/view_models/auth_view_model.dart';

/// Automatic sync (docs/budgets.md, Client request policy), no polling: full
/// sync on login and every resume (at least 5 minutes apart in
/// [SyncRepository.syncIfDue]); push only [debounce] after the last local
/// change ([syncChangesProvider]).
class SyncTrigger extends ConsumerStatefulWidget {
  const SyncTrigger({super.key, required this.child});

  final Widget child;

  /// Delay after the last local change (docs/budgets.md, Client request policy).
  static const debounce = Duration(seconds: 60);

  @override
  ConsumerState<SyncTrigger> createState() => _SyncTriggerState();
}

class _SyncTriggerState extends ConsumerState<SyncTrigger> {
  late final AppLifecycleListener _lifecycle;
  late final StreamSubscription<void> _changes;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => _run(trigger: _Trigger.resume),
    );
    // fireImmediately: auth finished before this widget was mounted (app opened
    // while logged in) also counts as logged in.
    ref.listenManual(authControllerProvider, (prev, next) {
      if (next.value?.status == AuthStatus.signedIn &&
          prev?.value?.status != AuthStatus.signedIn) {
        _run(trigger: _Trigger.signIn);
      }
    }, fireImmediately: true);
    _changes = ref.read(syncChangesProvider).listen((_) {
      _debounce?.cancel();
      _debounce = Timer(SyncTrigger.debounce, _run);
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_changes.cancel());
    _debounce?.cancel();
    super.dispose();
  }

  /// Debounced local change: push only. Resume / login: full sync (push + pull
  /// + book download).
  void _run({_Trigger trigger = _Trigger.change}) {
    final auth = ref.read(authControllerProvider).value;
    if (auth?.status != AuthStatus.signedIn) return;
    final repo = ref.read(syncRepositoryProvider);
    unawaited(switch (trigger) {
      _Trigger.change => repo.push(),
      _Trigger.resume => repo.syncIfDue(),
      _Trigger.signIn => repo.sync(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

enum _Trigger { change, resume, signIn }
