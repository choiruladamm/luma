import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';
import '../services/backend_client.dart';
import '../services/session_store.dart';

/// Hasil login. [switchedAccount] true = HP ini terakhir dipakai akun lain:
/// sesi BELUM disimpan, pemanggil konfirmasi dulu (board Akun 10) lalu
/// [AuthRepository.commit] atau [AuthRepository.discard].
class SignInResult {
  const SignInResult({
    required this.session,
    required this.switchedAccount,
    this.previousEmail,
  });

  final AuthSession session;
  final bool switchedAccount;

  /// Email akun lama di HP ini (dialog ganti akun).
  final String? previousEmail;

  AuthUser get user => session.user;
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

  Future<String?> lastUserId() => _store.readLastUserId();

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
    String? inviteCode,
  }) async => _keep(
    await _service.signUpEmail(
      name: name.trim(),
      email: email.trim(),
      password: password,
      inviteCode: inviteCode,
    ),
  );

  Future<SignInResult> signInGoogle({
    required String idToken,
    String? inviteCode,
  }) async => _keep(
    await _service.signInGoogle(idToken: idToken, inviteCode: inviteCode),
  );

  /// Simpan sesi setelah ganti akun dikonfirmasi.
  Future<void> commit(AuthSession session) async {
    await _store.writeToken(session.token);
    await _store.writeLastUserId(session.user.id);
    await _store.writeLastUserEmail(session.user.email);
  }

  /// Ganti akun dibatalin: sesi baru dibuang di server (best effort), HP tetap
  /// milik akun lama.
  Future<void> discard(AuthSession session) async {
    try {
      await _service.signOut(session.token);
    } on BackendException {
      // Offline: token baru cuma hidup di server sampai kedaluwarsa.
    }
  }

  /// User dari server sekalian cek token. 401 dilempar apa adanya: token
  /// TETAP disimpan supaya app gak kekunci (banner "Login lagi", board Akun 12).
  Future<AuthUser?> currentUser() async {
    final token = await _store.readToken();
    if (token == null) return null;
    return _service.me(token);
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
    final switched = last != null && last != session.user.id;
    if (!switched) await commit(session);
    return SignInResult(
      session: session,
      switchedAccount: switched,
      previousEmail: switched ? await _store.readLastUserEmail() : null,
    );
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(authServiceProvider),
    ref.watch(sessionStoreProvider),
  ),
);
