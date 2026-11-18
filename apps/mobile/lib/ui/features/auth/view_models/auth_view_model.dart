import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/services/auth_service.dart';
import '../../../../data/services/backend_client.dart';

enum AuthStatus {
  /// No session on the phone: the router opens the Masuk screen.
  signedOut,

  /// Has a session (offline too): the app runs.
  signedIn,

  /// Server replied 401: the app keeps running, the shelf shows a "Login lagi" banner.
  expired,
}

class AuthState {
  const AuthState(this.status, {this.user, this.bannerDismissed = false});

  final AuthStatus status;

  /// Null until `/v1/me` answers (or offline).
  final AuthUser? user;

  /// Session-expired banner dismissed: shows again when the app is reopened.
  final bool bannerDismissed;

  bool get showExpiredBanner =>
      status == AuthStatus.expired && !bannerDismissed;

  AuthState copyWith({
    AuthStatus? status,
    AuthUser? user,
    bool? bannerDismissed,
  }) => AuthState(
    status ?? this.status,
    user: user ?? this.user,
    bannerDismissed: bannerDismissed ?? this.bannerDismissed,
  );
}

/// App-wide session (docs/backend.md, Authentication and accounts). The initial
/// check only reads the local token; `/v1/me` is checked in the background
/// without holding up the app.
class AuthController extends AsyncNotifier<AuthState> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  Future<AuthState> build() async {
    if (!await ref.watch(authRepositoryProvider).hasSession()) {
      return const AuthState(AuthStatus.signedOut);
    }
    unawaited(Future.microtask(_verify));
    return const AuthState(AuthStatus.signedIn);
  }

  Future<void> _verify() async {
    try {
      final user = await _repo.currentUser();
      if (user != null) _set((s) => s.copyWith(user: user));
    } on BackendException catch (e) {
      if (e.statusCode == 401) {
        _set((s) => s.copyWith(status: AuthStatus.expired));
      }
      // Offline / server down: keep running, check again when the app reopens.
    }
  }

  /// Login (or re-login) succeeded and its session is saved.
  void signedIn(AuthUser user) =>
      state = AsyncData(AuthState(AuthStatus.signedIn, user: user));

  /// Logout: local data stays, the router returns to the Masuk screen.
  Future<void> signOut() async {
    await _repo.signOut();
    state = const AsyncData(AuthState(AuthStatus.signedOut));
  }

  /// Deletes the account on the server, then returns to the Masuk screen. Throws on failure.
  Future<void> deleteAccount() async {
    await _repo.deleteAccount();
    state = const AsyncData(AuthState(AuthStatus.signedOut));
  }

  void dismissBanner() => _set((s) => s.copyWith(bannerDismissed: true));

  void _set(AuthState Function(AuthState) update) {
    final current = state.value;
    if (current != null) state = AsyncData(update(current));
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
