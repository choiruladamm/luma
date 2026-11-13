import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/local_data_repository.dart';
import '../../../../data/services/auth_service.dart';
import '../../../../data/services/backend_client.dart';
import '../../../../data/services/google_auth.dart';
import 'auth_view_model.dart';

/// Langkah layar Masuk (board Akun 01–07, 10).
enum LoginStep { start, invite, switchAccount }

/// Kenapa login gagal; tiap nilai punya copy sendiri (board Akun 03, 04, 07).
enum LoginError {
  network,
  rejected,
  invalidCredentials,
  userExists,
  passwordTooShort,
  inviteInvalid,
  inviteUsed,
}

class LoginState {
  const LoginState({
    this.step = LoginStep.start,
    this.loading = false,
    this.error,
    this.email,
    this.pendingSwitch,
  });

  final LoginStep step;
  final bool loading;
  final LoginError? error;

  /// Email yang lagi dipakai login ("Masuk sebagai …" di kode undangan).
  final String? email;

  /// Login sukses tapi akun beda dari akun terakhir di HP: nunggu konfirmasi.
  final SignInResult? pendingSwitch;

  LoginState copyWith({
    LoginStep? step,
    bool? loading,
    LoginError? error,
    bool clearError = false,
    String? email,
    SignInResult? pendingSwitch,
  }) => LoginState(
    step: step ?? this.step,
    loading: loading ?? this.loading,
    error: clearError ? null : error ?? this.error,
    email: email ?? this.email,
    pendingSwitch: pendingSwitch ?? this.pendingSwitch,
  );
}

typedef _Attempt = Future<SignInResult> Function(String? inviteCode);

class LoginViewModel extends Notifier<LoginState> {
  _Attempt? _pending;

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  LoginState build() => const LoginState();

  Future<void> signInGoogle() async {
    if (state.loading) return;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final idToken = await ref.read(googleIdTokenSourceProvider).idToken();
      // Jendela Google ditutup: balik ke awal tanpa pesan error.
      if (idToken == null) {
        state = state.copyWith(loading: false);
        return;
      }
      await _run(
        (code) => _repo.signInGoogle(idToken: idToken, inviteCode: code),
      );
    } on BackendException catch (e) {
      _fail(e);
    }
  }

  Future<void> signInEmail(String email, String password) => _start(
    email,
    (code) => _repo.signInEmail(email: email, password: password),
  );

  /// Daftar email (build dev): nama = bagian depan email.
  Future<void> signUpEmail(String email, String password) => _start(
    email,
    (code) => _repo.signUpEmail(
      name: email.trim().split('@').first,
      email: email,
      password: password,
      inviteCode: code,
    ),
  );

  /// Kirim ulang login terakhir bareng kode undangan.
  Future<void> submitInvite(String code) async {
    final attempt = _pending;
    if (attempt == null || state.loading || code.trim().isEmpty) return;
    await _run(attempt, inviteCode: code);
  }

  /// Kode diubah: tombol Lanjut nyala lagi.
  void editInvite() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }

  /// "Ganti" di layar kode undangan: pilih akun lain.
  void backToStart() {
    _pending = null;
    state = const LoginState();
  }

  /// "Hapus isi HP & lanjut" (board Akun 10).
  Future<void> confirmSwitch() async {
    final result = state.pendingSwitch;
    if (result == null || state.loading) return;
    state = state.copyWith(loading: true);
    await ref.read(localDataRepositoryProvider).wipeBooks();
    await _repo.commit(result.session);
    _done(result);
  }

  /// "Pakai akun lama aja": sesi baru dibuang, HP tetap punya akun lama.
  Future<void> keepOldAccount() async {
    final result = state.pendingSwitch;
    if (result != null) await _repo.discard(result.session);
    backToStart();
  }

  Future<void> _start(String email, _Attempt attempt) async {
    if (state.loading) return;
    state = state.copyWith(
      loading: true,
      clearError: true,
      email: email.trim(),
    );
    await _run(attempt);
  }

  Future<void> _run(_Attempt attempt, {String? inviteCode}) async {
    _pending = attempt;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final result = await attempt(inviteCode);
      if (result.switchedAccount) {
        state = LoginState(
          step: LoginStep.switchAccount,
          email: result.user.email,
          pendingSwitch: result,
        );
        return;
      }
      _done(result);
    } on BackendException catch (e) {
      _fail(e);
    }
  }

  void _done(SignInResult result) {
    _pending = null;
    ref.read(authControllerProvider.notifier).signedIn(result.user);
    state = const LoginState();
  }

  void _fail(BackendException e) {
    final error = loginErrorFor(e.code, e.statusCode);
    final invite = AuthErrorCode.inviteCodes.contains(e.code);
    state = state.copyWith(
      loading: false,
      step: invite ? LoginStep.invite : state.step,
      error: error,
      clearError: error == null,
    );
  }
}

/// Kode error server → copy. `INVITE_CODE_REQUIRED` bukan error: cuma buka
/// layar kode undangan.
LoginError? loginErrorFor(String code, int? status) {
  if (code == AuthErrorCode.inviteRequired) return null;
  if (code == AuthErrorCode.invalidInvite) return LoginError.inviteInvalid;
  if (code == AuthErrorCode.inviteUsed) return LoginError.inviteUsed;
  if (code == AuthErrorCode.invalidCredentials) {
    return LoginError.invalidCredentials;
  }
  if (code == AuthErrorCode.userExists) return LoginError.userExists;
  if (code == 'PASSWORD_TOO_SHORT') return LoginError.passwordTooShort;
  if (code == 'NETWORK' || (status ?? 0) >= 500) return LoginError.network;
  return LoginError.rejected;
}

final loginViewModelProvider =
    NotifierProvider.autoDispose<LoginViewModel, LoginState>(
      LoginViewModel.new,
    );
