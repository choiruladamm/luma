import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';
import '../services/backend_client.dart';
import '../services/session_store.dart';

/// Hasil login: [switchedAccount] true kalau HP ini terakhir dipakai akun
/// lain, jadi data lokal harus dikonfirmasi-hapus dulu sebelum lanjut
/// (docs/backend.md, Sesi & akun).
class SignInResult {
  const SignInResult({required this.user, required this.switchedAccount});

  final AuthUser user;
  final bool switchedAccount;
}

/// Sumber kebenaran sesi di HP: token di secure storage, login wajib
/// (docs/backend.md, Sesi & akun). Cek "sudah login" gak memanggil server,
/// jadi app kebuka offline.
class AuthRepository {
  AuthRepository(this._service, this._store);

  final AuthService _service;
  final SessionStore _store;

  /// Batas panggilan hapus akun saat server balas "masih membersihkan".
  static const deleteAttempts = 5;

  Future<bool> hasSession() async => await _store.readToken() != null;

  Future<String?> token() => _store.readToken();

  Future<SignInResult> signInEmail({
    required String email,
    required String password,
  }) async => _keep(
    await _service.signInEmail(email: email.trim(), password: password),
  );

  Future<SignInResult> signUpEmail({
    required String name,
    required String email,
    required String password,
    required String inviteCode,
  }) async => _keep(
    await _service.signUpEmail(
      name: name.trim(),
      email: email.trim(),
      password: password,
      inviteCode: inviteCode,
    ),
  );

  /// User dari server, sekalian cek token masih berlaku. 401 → token dibuang.
  Future<AuthUser?> currentUser() async {
    final token = await _store.readToken();
    if (token == null) return null;
    try {
      return await _service.me(token);
    } on BackendException catch (e) {
      if (e.statusCode == 401) await _store.clearToken();
      rethrow;
    }
  }

  /// Logout: token lokal selalu dihapus walau server gak kejangkau. Data lokal tetap.
  Future<void> signOut() async {
    final token = await _store.readToken();
    await _store.clearToken();
    if (token == null) return;
    try {
      await _service.signOut(token);
    } on BackendException {
      // Offline / sesi udah mati: cukup token lokal yang hilang.
    }
  }

  /// Hapus akun + data server. Sukses → token dan penanda akun terakhir dihapus.
  Future<void> deleteAccount() async {
    final token = await _store.readToken();
    if (token == null) return;
    for (var i = 0; i < deleteAttempts; i++) {
      if (await _service.deleteAccount(token)) {
        await _store.clearToken();
        await _store.clearLastUserId();
        return;
      }
    }
    throw const BackendException(
      code: 'DELETE_PENDING',
      message: 'Account deletion still in progress',
    );
  }

  Future<SignInResult> _keep(AuthSession session) async {
    final last = await _store.readLastUserId();
    await _store.writeToken(session.token);
    await _store.writeLastUserId(session.user.id);
    return SignInResult(
      user: session.user,
      switchedAccount: last != null && last != session.user.id,
    );
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(authServiceProvider),
    ref.watch(sessionStoreProvider),
  ),
);
