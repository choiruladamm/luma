import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';
import '../services/backend_client.dart';
import '../services/session_store.dart';

/// Result of a sign-in. [switchedAccount] true means this phone last belonged to a
/// different account: the session is NOT stored yet, and the caller confirms first
/// (board Akun 10), then calls [AuthRepository.commit] or [AuthRepository.discard].
class SignInResult {
  const SignInResult({
    required this.session,
    required this.switchedAccount,
    this.previousEmail,
  });

  final AuthSession session;
  final bool switchedAccount;

  /// Email of the previous account on this phone (shown in the account-switch dialog).
  final String? previousEmail;

  AuthUser get user => session.user;
}

/// Source of truth for the session on the phone: the token lives in secure storage
/// and sign-in is required (docs/backend.md, Authentication and accounts). The
/// "already signed in" check never calls the server, so the app opens offline.
class AuthRepository {
  AuthRepository(this._service, this._store);

  final AuthService _service;
  final SessionStore _store;

  /// Maximum account-deletion calls while the server keeps answering "still cleaning up".
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

  /// Stores the session once the account switch is confirmed.
  Future<void> commit(AuthSession session) async {
    await _store.writeToken(session.token);
    await _store.writeLastUserId(session.user.id);
    await _store.writeLastUserEmail(session.user.email);
  }

  /// Cancels an account switch: the new session is dropped on the server (best
  /// effort) and the phone stays with the previous account.
  Future<void> discard(AuthSession session) async {
    try {
      await _service.signOut(session.token);
    } on BackendException {
      // Offline: the new token only lives on the server until it expires.
    }
  }

  /// Fetches the user from the server, which also validates the token. A 401 is
  /// thrown as is: the token stays stored so the app isn't locked out ("Login lagi"
  /// banner, board Akun 12).
  Future<AuthUser?> currentUser() async {
    final token = await _store.readToken();
    if (token == null) return null;
    return _service.me(token);
  }

  /// Signs out: the local token is always deleted, even if the server is unreachable. Local data stays.
  Future<void> signOut() async {
    final token = await _store.readToken();
    await _store.clearToken();
    if (token == null) return;
    try {
      await _service.signOut(token);
    } on BackendException {
      // Offline or session already dead: deleting the local token is enough.
    }
  }

  /// Deletes the account and its server data. On success the token and the last-account marker are deleted.
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
