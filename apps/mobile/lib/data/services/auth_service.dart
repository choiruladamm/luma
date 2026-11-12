import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backend_client.dart';

/// User dari backend (`/v1/me`, respons login). Field sama dengan fixture
/// kontrak `apps/backend/test/fixtures/contract/me.json`.
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

/// Kode error auth dari server (docs/backend.md, Auth).
abstract final class AuthErrorCode {
  static const invalidInvite = 'INVALID_INVITE_CODE';
  static const invalidCredentials = 'INVALID_EMAIL_OR_PASSWORD';
  static const userExists = 'USER_ALREADY_EXISTS_USE_ANOTHER_EMAIL';
  static const unauthorized = 'UNAUTHORIZED';
}

/// Panggilan `/v1/auth/*` dan `/v1/me`. Gak nyimpen apa-apa: penyimpanan
/// token di [AuthRepository].
class AuthService {
  AuthService(this._client);

  final BackendClient _client;

  static const inviteHeader = 'x-invite-code';

  Future<AuthSession> signUpEmail({
    required String name,
    required String email,
    required String password,
    required String inviteCode,
  }) async {
    final res = await _client.request(
      'POST',
      '/v1/auth/sign-up/email',
      body: {'name': name, 'email': email, 'password': password},
      headers: {inviteHeader: inviteCode.trim()},
      retry: false,
    );
    return _session(res.headers.value('set-auth-token'), res.data!);
  }

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

  /// True kalau akun sudah terhapus; false = server masih membersihkan file
  /// (202), panggil lagi.
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
