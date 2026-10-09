import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// API key OpenRouter di Keychain (iOS) / Keystore (Android). Sengaja gak di
/// Drift: gak ikut backup (docs/llm.md, docs/backup.md).
class ApiKeyStore {
  ApiKeyStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;
  static const _key = 'openrouter_api_key';

  /// Null kalau belum diisi.
  Future<String?> read() async {
    final key = await _storage.read(key: _key);
    return key == null || key.isEmpty ? null : key;
  }

  /// Kosong = hapus.
  Future<void> write(String key) {
    final trimmed = key.trim();
    return trimmed.isEmpty
        ? _storage.delete(key: _key)
        : _storage.write(key: _key, value: trimmed);
  }
}

final apiKeyStoreProvider = Provider<ApiKeyStore>((ref) => ApiKeyStore());
