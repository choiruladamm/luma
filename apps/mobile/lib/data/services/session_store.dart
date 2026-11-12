import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Token sesi backend + id akun terakhir di Keychain / Keystore. Gak di Drift:
/// gak ikut backup (docs/backend.md, Sesi & akun).
class SessionStore {
  SessionStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;
  static const _tokenKey = 'backend_session_token';
  static const _lastUserKey = 'backend_last_user_id';

  /// Null = belum login → app buka layar Masuk.
  Future<String?> readToken() async {
    final token = await _storage.read(key: _tokenKey);
    return token == null || token.isEmpty ? null : token;
  }

  Future<void> writeToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  /// Akun yang terakhir login di HP ini, tetap ada setelah logout: dipakai
  /// untuk deteksi ganti akun (data lokal milik akun lain).
  Future<String?> readLastUserId() => _storage.read(key: _lastUserKey);

  Future<void> writeLastUserId(String id) =>
      _storage.write(key: _lastUserKey, value: id);

  Future<void> clearLastUserId() => _storage.delete(key: _lastUserKey);
}

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());
