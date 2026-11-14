import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/sync_repository.dart';
import '../../auth/view_models/auth_view_model.dart';

/// Sync otomatis (docs/backend.md, Sync antar device), tanpa polling: sync
/// penuh saat login dan tiap resume (jarak min 5 menit di
/// [SyncRepository.syncIfDue]); push aja [debounce] setelah perubahan lokal
/// terakhir ([syncChangesProvider]).
class SyncTrigger extends ConsumerStatefulWidget {
  const SyncTrigger({super.key, required this.child});

  final Widget child;

  /// Jeda setelah perubahan lokal terakhir (docs/backend.md, Aturan client).
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
    // fireImmediately: auth udah kelar sebelum widget ini dipasang (app
    // dibuka dalam kondisi login) juga dihitung login.
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

  /// Debounce perubahan lokal: push aja. Resume / login: sync penuh (push +
  /// pull + download buku).
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
