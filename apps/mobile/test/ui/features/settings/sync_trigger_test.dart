import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/sync_repository.dart';
import 'package:luma/ui/features/auth/view_models/auth_view_model.dart';
import 'package:luma/ui/features/settings/views/sync_trigger.dart';

class _Auth extends AuthController {
  _Auth(this.initial);

  final AuthState initial;

  @override
  Future<AuthState> build() async => initial;

  void set(AuthStatus status) => state = AsyncData(AuthState(status));
}

class _Sync extends Fake implements SyncRepository {
  final calls = <String>[];

  @override
  Future<int> push() async {
    calls.add('push');
    return 0;
  }

  @override
  Future<void> syncIfDue() async => calls.add('due');

  @override
  Future<void> sync() async => calls.add('sync');
}

void main() {
  late StreamController<void> changes;
  late _Sync sync;
  late _Auth auth;

  setUp(() {
    changes = StreamController<void>.broadcast();
    sync = _Sync();
  });
  tearDown(() => unawaited(changes.close()));

  Future<void> pump(WidgetTester tester, AuthStatus status) async {
    auth = _Auth(AuthState(status));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => auth),
          syncRepositoryProvider.overrideWithValue(sync),
          syncChangesProvider.overrideWithValue(changes.stream),
        ],
        child: const SyncTrigger(child: SizedBox()),
      ),
    );
    await tester.pump();
  }

  testWidgets('pushes 60 s after the last local change', (tester) async {
    await pump(tester, AuthStatus.signedIn);
    sync.calls.clear();

    changes.add(null);
    await tester.pump(const Duration(seconds: 30));
    changes.add(null); // perubahan baru ngulang jeda
    await tester.pump(const Duration(seconds: 59));
    expect(sync.calls, isEmpty);

    await tester.pump(const Duration(seconds: 1));
    expect(sync.calls, ['push']);
  });

  testWidgets('resume asks for a due sync', (tester) async {
    await pump(tester, AuthStatus.signedIn);
    sync.calls.clear();

    for (final s in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }

    expect(sync.calls, ['due']);
  });

  testWidgets('signing in syncs once; signed out never syncs', (tester) async {
    await pump(tester, AuthStatus.signedOut);
    changes.add(null);
    await tester.pump(SyncTrigger.debounce);
    expect(sync.calls, isEmpty);

    auth.set(AuthStatus.signedIn);
    await tester.pump();
    expect(sync.calls, ['sync']);
  });

  testWidgets('opening the app already signed in syncs once', (tester) async {
    // Auth kelar sebelum SyncTrigger dipasang (router nge-watch duluan):
    // gak ada perubahan status yang bisa didengerin.
    auth = _Auth(const AuthState(AuthStatus.signedIn));
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(() => auth),
        syncRepositoryProvider.overrideWithValue(sync),
        syncChangesProvider.overrideWithValue(changes.stream),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const SyncTrigger(child: SizedBox()),
      ),
    );
    await tester.pump();

    expect(sync.calls, ['sync']);
  });
}
