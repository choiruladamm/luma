import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/services/backend_client.dart';
import 'package:luma/data/services/google_auth.dart';
import 'package:luma/routing/router.dart';
import 'package:luma/ui/features/auth/view_models/auth_view_model.dart';
import 'package:luma/ui/features/auth/view_models/login_view_model.dart';

import '../../../support/backend_fakes.dart';
import 'auth_fakes.dart';

void main() {
  late AuthHarness h;
  late ProviderContainer container;

  LoginViewModel vm() => container.read(loginViewModelProvider.notifier);
  LoginState state() => container.read(loginViewModelProvider);
  Future<AuthState> auth() => container.read(authControllerProvider.future);

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    h = AuthHarness();
    container = ProviderContainer(overrides: h.overrides);
    addTearDown(container.dispose);
    // autoDispose: tetap hidup sepanjang test.
    container.listen(loginViewModelProvider, (_, _) {});
    expect((await auth()).status, AuthStatus.signedOut);
  });

  group('Google', () {
    test('success signs in and stores the session (contract)', () async {
      h.adapter.queue.add(fromContract(contract('auth-sign-in-email')));

      await vm().signInGoogle();

      expect((await auth()).status, AuthStatus.signedIn);
      expect((await auth()).user?.name, 'Adam');
      expect(await h.repo.hasSession(), isTrue);
      expect(state().step, LoginStep.start);
      expect(state().loading, isFalse);
    });

    test('closing the Google window goes back quietly', () async {
      h.google.result = null;

      await vm().signInGoogle();

      expect(state().loading, isFalse);
      expect(state().error, isNull);
      expect(h.adapter.requests, isEmpty);
    });

    test('network failure shows the network footnote', () async {
      h.adapter.queue.add(DioExceptionType.connectionError);

      await vm().signInGoogle();

      expect(state().error, LoginError.network);
      expect((await auth()).status, AuthStatus.signedOut);
    });

    test('an unconfigured build is a rejection, not a crash', () async {
      h.google.result = const BackendException(
        code: googleNotConfigured,
        message: 'x',
      );

      await vm().signInGoogle();

      expect(state().error, LoginError.rejected);
    });
  });

  group('invite code', () {
    test(
      'a new account without a code opens the invite step (contract)',
      () async {
        h.adapter.queue.add(
          fromContract(contract('error-invite-code-required')),
        );

        await vm().signUpEmail('baru@luma.test', 'rahasia-banget-123');

        expect(state().step, LoginStep.invite);
        expect(state().error, isNull);
        expect(state().email, 'baru@luma.test');
      },
    );

    test(
      'used code shows its note; editing clears it; a good code signs in',
      () async {
        h.adapter.queue
          ..add(fromContract(contract('error-invite-code-required')))
          ..add(fromContract(contract('error-invite-code-used')))
          ..add(fromContract(contract('auth-sign-up-email')));
        await vm().signUpEmail('baru@luma.test', 'rahasia-banget-123');

        await vm().submitInvite('LUMA-4HJP');
        expect(state().error, LoginError.inviteUsed);
        expect(h.adapter.requests.last.headers['x-invite-code'], 'LUMA-4HJP');

        vm().editInvite();
        expect(state().error, isNull);

        await vm().submitInvite('luma7q2k');
        expect(h.adapter.requests.last.headers['x-invite-code'], 'luma7q2k');
        expect((await auth()).status, AuthStatus.signedIn);
      },
    );

    test('unknown code shows the "wrong code" note (contract)', () async {
      h.adapter.queue
        ..add(fromContract(contract('error-invite-code-required')))
        ..add(fromContract(contract('error-invalid-invite-code')));
      await vm().signUpEmail('baru@luma.test', 'rahasia-banget-123');

      await vm().submitInvite('SALAH');

      expect(state().error, LoginError.inviteInvalid);
      expect(state().step, LoginStep.invite);
    });

    test('"Change" goes back to the start', () async {
      h.adapter.queue.add(fromContract(contract('error-invite-code-required')));
      await vm().signUpEmail('baru@luma.test', 'rahasia-banget-123');

      vm().backToStart();

      expect(state().step, LoginStep.start);
    });
  });

  group('email (dev build)', () {
    test('wrong password maps to its own copy (contract)', () async {
      h.adapter.queue.add(fromContract(contract('error-invalid-credentials')));

      await vm().signInEmail('adam@luma.test', 'salah');

      expect(state().error, LoginError.invalidCredentials);
    });
  });

  group('switching account', () {
    setUp(() async {
      await h.store.writeLastUserId('akun-lama');
      await h.store.writeLastUserEmail('lama@luma.test');
      h.adapter.queue.add(fromContract(contract('auth-sign-in-email')));
      await vm().signInEmail('adam@luma.test', 'rahasia-banget-123');
    });

    test('pauses on the switch step without saving the session', () async {
      expect(state().step, LoginStep.switchAccount);
      expect(state().pendingSwitch?.previousEmail, 'lama@luma.test');
      expect(await h.repo.hasSession(), isFalse);
      expect((await auth()).status, AuthStatus.signedOut);
    });

    test('confirm wipes the phone, then saves and signs in', () async {
      await vm().confirmSwitch();

      expect(h.local.wipes, 1);
      expect(await h.repo.hasSession(), isTrue);
      expect(await h.store.readLastUserId(), 'user-1');
      expect((await auth()).status, AuthStatus.signedIn);
    });

    test('keeping the old account discards the new session', () async {
      h.adapter.queue.add(json(200, {'success': true}));

      await vm().keepOldAccount();

      expect(h.local.wipes, 0);
      expect(h.adapter.requests.last.uri.path, '/v1/auth/sign-out');
      expect(await h.store.readLastUserId(), 'akun-lama');
      expect(state().step, LoginStep.start);
    });
  });

  group('loginErrorFor', () {
    test('maps server codes to copy', () {
      expect(loginErrorFor('INVITE_CODE_REQUIRED', 403), isNull);
      expect(loginErrorFor('NETWORK', null), LoginError.network);
      expect(loginErrorFor('INTERNAL_ERROR', 500), LoginError.network);
      expect(
        loginErrorFor('PASSWORD_TOO_SHORT', 400),
        LoginError.passwordTooShort,
      );
      expect(
        loginErrorFor('USER_ALREADY_EXISTS_USE_ANOTHER_EMAIL', 422),
        LoginError.userExists,
      );
      expect(loginErrorFor('FORBIDDEN', 403), LoginError.rejected);
    });
  });

  group('authRedirect', () {
    test('signed out is locked to the login screen', () {
      expect(authRedirect(AuthStatus.signedOut, '/'), Routes.login);
      expect(authRedirect(AuthStatus.signedOut, '/settings'), Routes.login);
      expect(authRedirect(AuthStatus.signedOut, Routes.login), isNull);
    });

    test('signed in leaves login for the shelf', () {
      expect(authRedirect(AuthStatus.signedIn, Routes.login), Routes.home);
      expect(authRedirect(AuthStatus.signedIn, '/'), isNull);
    });

    test('expired sessions may open login from the banner; unknown never redirects', () {
      expect(authRedirect(AuthStatus.expired, Routes.login), isNull);
      expect(authRedirect(AuthStatus.expired, '/'), isNull);
      expect(authRedirect(null, '/'), isNull);
    });
  });

  group('AuthController', () {
    test('a stored session opens the app, then 401 marks it expired', () async {
      await h.store.writeToken('mati');
      h.adapter.queue.add(fromContract(contract('error-unauthorized')));
      final fresh = ProviderContainer(overrides: h.overrides);
      addTearDown(fresh.dispose);

      expect(
        (await fresh.read(authControllerProvider.future)).status,
        AuthStatus.signedIn,
      );
      await pumpEventQueue();

      final after = fresh.read(authControllerProvider).value!;
      expect(after.status, AuthStatus.expired);
      expect(after.showExpiredBanner, isTrue);

      fresh.read(authControllerProvider.notifier).dismissBanner();
      expect(
        fresh.read(authControllerProvider).value!.showExpiredBanner,
        isFalse,
      );
    });

    test('offline at start keeps the app signed in', () async {
      await h.store.writeToken('tok');
      h.adapter.queue.addAll(List.filled(3, DioExceptionType.connectionError));
      final fresh = ProviderContainer(overrides: h.overrides);
      addTearDown(fresh.dispose);

      await fresh.read(authControllerProvider.future);
      await pumpEventQueue();

      expect(
        fresh.read(authControllerProvider).value!.status,
        AuthStatus.signedIn,
      );
    });

    test('sign out clears the session and returns to signed out', () async {
      await h.store.writeToken('tok');
      h.adapter.queue
        ..add(fromContract(contract('me')))
        ..add(json(200, {'success': true}));
      final fresh = ProviderContainer(overrides: h.overrides);
      addTearDown(fresh.dispose);
      await fresh.read(authControllerProvider.future);
      await pumpEventQueue();

      await fresh.read(authControllerProvider.notifier).signOut();

      expect(
        fresh.read(authControllerProvider).value!.status,
        AuthStatus.signedOut,
      );
      expect(await h.repo.hasSession(), isFalse);
    });
  });
}
