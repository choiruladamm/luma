import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// API key OpenRouter di Keychain iPhone. Sengaja gak di Drift: gak ikut
/// backup (docs bagian 9 & 10).
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

/// API key buat dicek di Pengaturan; dibaca ulang tiap Pengaturan dibuka.
/// Yang manggil LLM baca langsung dari [ApiKeyStore] tiap request, biar
/// gak pernah pake key basi.
final apiKeyProvider = FutureProvider.autoDispose<String?>(
  (ref) => ref.watch(apiKeyStoreProvider).read(),
);
