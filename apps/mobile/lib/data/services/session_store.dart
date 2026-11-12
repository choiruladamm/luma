import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Token sesi backend + id akun terakhir di Keychain / Keystore. Gak di Drift:
/// gak ikut backup (docs/backend.md, Sesi & akun).
class SessionStore {
  SessionStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;
  static const _tokenKey = 'backend_session_token';
  static const _lastUserKey = 'backend_last_user_id';
  static const _subsidyKey = 'ai_subsidy_key';
  static const _subsidyExpiresKey = 'ai_subsidy_key_expires_at';

  /// Null = belum login → app buka layar Masuk.
  Future<String?> readToken() async {
    final token = await _storage.read(key: _tokenKey);
    return token == null || token.isEmpty ? null : token;
  }

  Future<void> writeToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  /// Logout: token + key AI subsidi milik akun itu ikut dibuang.
  Future<void> clearToken() async {
    await _storage.delete(key: _tokenKey);
    await clearSubsidyKey();
  }

  /// Key OpenRouter subsidi dari backend (docs/backend.md, AI). Null kalau
  /// belum pernah diambil atau formatnya rusak.
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

  /// Akun yang terakhir login di HP ini, tetap ada setelah logout: dipakai
  /// untuk deteksi ganti akun (data lokal milik akun lain).
  Future<String?> readLastUserId() => _storage.read(key: _lastUserKey);

  Future<void> writeLastUserId(String id) =>
      _storage.write(key: _lastUserKey, value: id);

  Future<void> clearLastUserId() => _storage.delete(key: _lastUserKey);
}

class SubsidyKey {
  const SubsidyKey({required this.key, required this.expiresAt});

  final String key;
  final DateTime expiresAt;
}

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());
