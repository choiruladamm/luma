import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ai_key_service.dart';
import '../services/api_key_store.dart';
import '../services/session_store.dart';

/// Key OpenRouter yang dipakai panggilan AI: `key = byok ?? subsidi`
/// (docs/backend.md, AI subsidi + BYOK). Bentuknya [ApiKeyStore] supaya
/// pemanggil lama cukup ganti provider; [write] tetap nulis key BYOK.
///
/// Key subsidi diambil dari backend cuma kalau perlu (belum ada, hampir
/// kedaluwarsa, atau ditolak OpenRouter), jadi gak ada polling.
class AiKeyRepository implements ApiKeyStore {
  AiKeyRepository(
    this._byok,
    this._session,
    this._service, {
    this._now = DateTime.now,
  });

  final ApiKeyStore _byok;
  final SessionStore _session;
  final AiKeyService _service;
  final DateTime Function() _now;

  /// Diminta baru sehari sebelum kedaluwarsa (sama dengan rotasi server).
  static const refreshBefore = Duration(days: 1);

  /// Key subsidi yang barusan ditolak OpenRouter (401): baca berikutnya rotasi.
  String? _rejected;
  Future<String?>? _inFlight;

  @override
  Future<void> write(String key) => _byok.write(key);

  @override
  Future<String?> read() async {
    final own = await _byok.read();
    if (own != null) return own;
    // Beberapa layar bisa minta bersamaan: satu panggilan backend aja.
    return _inFlight ??= _subsidy().whenComplete(() => _inFlight = null);
  }

  /// Dipanggil [OpenRouterService] saat OpenRouter balas 401 untuk [key].
  void markRejected(String key) => _rejected = key;

  /// True kalau [key] adalah key subsidi (bukan BYOK): buat pesan 402.
  Future<bool> isSubsidy(String key) async =>
      (await _session.readSubsidyKey())?.key == key;

  Future<String?> _subsidy() async {
    SubsidyKey? stored;
    try {
      stored = await _session.readSubsidyKey();
      final rejected = stored != null && stored.key == _rejected;
      final fresh =
          stored != null && stored.expiresAt.difference(_now()) > refreshBefore;
      if (stored != null && fresh && !rejected) return stored.key;

      final token = await _session.readToken();
      if (token == null) return null;
      final issued = await _service.issueKey(token, rotate: rejected);
      await _session.writeSubsidyKey(issued);
      _rejected = null;
      return issued.key;
    } on Object {
      // Offline / backend mati: key lama yang belum kedaluwarsa masih kepake.
      final usable = stored != null && stored.expiresAt.isAfter(_now());
      return usable ? stored.key : null;
    }
  }
}

final aiKeyRepositoryProvider = Provider<AiKeyRepository>(
  (ref) => AiKeyRepository(
    ref.watch(apiKeyStoreProvider),
    ref.watch(sessionStoreProvider),
    ref.watch(aiKeyServiceProvider),
  ),
);
