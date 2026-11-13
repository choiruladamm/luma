import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/services/auth_service.dart';
import '../../../../data/services/backend_client.dart';

enum AuthStatus {
  /// Belum ada sesi di HP: router buka layar Masuk.
  signedOut,

  /// Ada sesi (offline juga): app jalan.
  signedIn,

  /// Server balas 401: app tetap jalan, Rak nampilin banner "Login lagi".
  expired,
}

class AuthState {
  const AuthState(this.status, {this.user, this.bannerDismissed = false});

  final AuthStatus status;

  /// Null sampai `/v1/me` kejawab (atau offline).
  final AuthUser? user;

  /// Banner sesi habis ditutup: muncul lagi saat app dibuka ulang.
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

/// Sesi app-wide (docs/backend.md, Sesi & akun). Cek awal cuma baca token
/// lokal; `/v1/me` dicek di latar tanpa nahan app.
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
      // Offline / server mati: tetap jalan, cek lagi pas app dibuka ulang.
    }
  }

  /// Login (atau login lagi) berhasil dan sesinya udah disimpan.
  void signedIn(AuthUser user) =>
      state = AsyncData(AuthState(AuthStatus.signedIn, user: user));

  /// Logout: data lokal tetap, router balik ke layar Masuk.
  Future<void> signOut() async {
    await _repo.signOut();
    state = const AsyncData(AuthState(AuthStatus.signedOut));
  }

  /// Hapus akun di server, lalu balik ke layar Masuk. Gagal → dilempar.
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
