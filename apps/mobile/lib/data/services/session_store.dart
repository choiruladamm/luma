import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps the backend session token and last account id in Keychain / Keystore.
///
/// Not in Drift, so it stays out of backups (docs/backend.md, Authentication and accounts).
class SessionStore {
  SessionStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;
  static const _tokenKey = 'backend_session_token';
  static const _lastUserKey = 'backend_last_user_id';
  static const _lastEmailKey = 'backend_last_user_email';
  static const _subsidyKey = 'ai_subsidy_key';
  static const _subsidyExpiresKey = 'ai_subsidy_key_expires_at';

  /// Returns the session token, or null when not signed in (the app opens the Masuk screen).
  Future<String?> readToken() async {
    final token = await _storage.read(key: _tokenKey);
    return token == null || token.isEmpty ? null : token;
  }

  Future<void> writeToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  /// Clears the token on logout, together with that account's subsidized AI key.
  Future<void> clearToken() async {
    await _storage.delete(key: _tokenKey);
    await clearSubsidyKey();
  }

  /// Returns the subsidized OpenRouter key from the backend (docs/backend.md, AI subsidy).
  ///
  /// Null when it was never fetched or its stored format is corrupt.
  Future<SubsidyKey?> readSubsidyKey() async {
    final key = await _storage.read(key: _subsidyKey);
    final expires = DateTime.tryParse(
      await _storage.read(key: _subsidyExpiresKey) ?? '',
    );
    if (key == null || key.isEmpty || expires == null) return null;
    return SubsidyKey(key: key, expiresAt: expires);
  }

  Future<void> writeSubsidyKey(SubsidyKey value) async {
    await _storage.write(key: _subsidyKey, value: value.key);
    await _storage.write(
      key: _subsidyExpiresKey,
      value: value.expiresAt.toUtc().toIso8601String(),
    );
  }

  Future<void> clearSubsidyKey() async {
    await _storage.delete(key: _subsidyKey);
    await _storage.delete(key: _subsidyExpiresKey);
  }

  /// Returns the account that last signed in on this phone.
  ///
  /// It survives logout so the app can detect an account switch (local data
  /// that belongs to another account).
  Future<String?> readLastUserId() => _storage.read(key: _lastUserKey);

  Future<void> writeLastUserId(String id) =>
      _storage.write(key: _lastUserKey, value: id);

  Future<void> clearLastUserId() async {
    await _storage.delete(key: _lastUserKey);
    await _storage.delete(key: _lastEmailKey);
  }

  /// Returns the last account's email, shown in the account-switch dialog ("Isi HP ini punya …").
  Future<String?> readLastUserEmail() => _storage.read(key: _lastEmailKey);

  Future<void> writeLastUserEmail(String email) =>
      _storage.write(key: _lastEmailKey, value: email);
}

class SubsidyKey {
  const SubsidyKey({required this.key, required this.expiresAt});

  final String key;
  final DateTime expiresAt;
}

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());
