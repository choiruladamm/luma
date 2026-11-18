import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backend_client.dart';

/// Represents a user returned by the backend (`/v1/me` and login responses).
///
/// Fields match the contract fixture `apps/backend/test/fixtures/contract/me.json`.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    this.image,
  });

  factory AuthUser.fromJson(Map<String, Object?> json) => AuthUser(
    id: json['id']! as String,
    name: json['name']! as String,
    email: json['email']! as String,
    image: json['image'] as String?,
  );

  final String id;
  final String name;
  final String email;
  final String? image;
}

class AuthSession {
  const AuthSession({required this.token, required this.user});

  final String token;
  final AuthUser user;
}

/// Auth error codes returned by the server (docs/backend.md, Authentication and accounts).
abstract final class AuthErrorCode {
  static const invalidInvite = 'INVALID_INVITE_CODE';
  static const invalidCredentials = 'INVALID_EMAIL_OR_PASSWORD';
  static const userExists = 'USER_ALREADY_EXISTS_USE_ANOTHER_EMAIL';
  static const unauthorized = 'UNAUTHORIZED';

  /// A new account without an invite code; the UI asks for one (board Akun 06).
  static const inviteRequired = 'INVITE_CODE_REQUIRED';
  static const inviteUsed = 'INVITE_CODE_USED';

  static const inviteCodes = {invalidInvite, inviteRequired, inviteUsed};
}

/// Calls `/v1/auth/*` and `/v1/me`.
///
/// Stores nothing; [AuthRepository] persists the token.
class AuthService {
  AuthService(this._client);

  final BackendClient _client;

  static const inviteHeader = 'x-invite-code';

  Future<AuthSession> signUpEmail({
    required String name,
    required String email,
    required String password,
    String? inviteCode,
  }) async {
    final res = await _client.request(
      'POST',
      '/v1/auth/sign-up/email',
      body: {'name': name, 'email': email, 'password': password},
      headers: _invite(inviteCode),
      retry: false,
    );
    return _session(res.headers.value('set-auth-token'), res.data!);
  }

  /// Signs in with a Google ID token from `google_sign_in`.
  ///
  /// A new account needs [inviteCode] during the beta; the server answers
  /// `INVITE_CODE_REQUIRED` when it is empty.
  Future<AuthSession> signInGoogle({
    required String idToken,
    String? inviteCode,
  }) async {
    final res = await _client.request(
      'POST',
      '/v1/auth/sign-in/social',
      body: {
        'provider': 'google',
        'idToken': {'token': idToken},
      },
      headers: _invite(inviteCode),
      retry: false,
    );
    return _session(res.headers.value('set-auth-token'), res.data!);
  }

  Map<String, String> _invite(String? code) => {
    if (code != null && code.trim().isNotEmpty) inviteHeader: code.trim(),
  };

  Future<AuthSession> signInEmail({
    required String email,
    required String password,
  }) async {
    final res = await _client.request(
      'POST',
      '/v1/auth/sign-in/email',
      body: {'email': email, 'password': password},
      retry: false,
    );
    return _session(res.headers.value('set-auth-token'), res.data!);
  }

  Future<void> signOut(String token) async {
    await _client.request('POST', '/v1/auth/sign-out', body: {}, token: token);
  }

  Future<AuthUser> me(String token) async {
    final res = await _client.request('GET', '/v1/me', token: token);
    return AuthUser.fromJson(res.data!['user']! as Map<String, Object?>);
  }

  /// Returns true once the account is deleted.
  ///
  /// False means the server is still cleaning up files (202); call again.
  Future<bool> deleteAccount(String token) async {
    final res = await _client.request('DELETE', '/v1/me', token: token);
    return res.data?['status'] == 'deleted';
  }

  AuthSession _session(String? header, Map<String, Object?> body) =>
      AuthSession(
        token: header ?? body['token']! as String,
        user: AuthUser.fromJson(body['user']! as Map<String, Object?>),
      );
}

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(ref.watch(backendClientProvider)),
);
