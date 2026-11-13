import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/ai_reply.dart';
import '../services/ai_key_service.dart';
import '../services/backend_client.dart';
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
    } on BackendException catch (e) {
      // Akses kuota gratis dicabut: kartu "Akses AI gratis lo dicabut"
      // (board Kuota AI 12), bukan "API key belum diisi".
      if (e.code == aiBannedCode) {
        throw const AiException(
          AiError.http,
          status: 403,
          detail: aiBannedCode,
        );
      }
      final usable = stored != null && stored.expiresAt.isAfter(_now());
      if (usable) return stored.key;
      // Ada sesi tapi backend gak kejangkau: layar AI nampilin error
      // jaringan, bukan minta key.
      if (e.code == 'NETWORK') throw const AiException(AiError.network);
      return null;
    } on Object {
      // Secure storage gagal dibaca dll: key lama yang belum kedaluwarsa
      // masih kepake.
      final usable = stored != null && stored.expiresAt.isAfter(_now());
      return usable ? stored.key : null;
    }
  }
}

/// Kode server saat akun gak boleh pakai kuota gratis (docs/backend.md, AI).
/// Dipakai juga sebagai [AiException.detail] supaya UI bisa ngenalin.
const aiBannedCode = 'AI_BANNED';

/// AI gagal karena kuota gratis abis (402 dengan key subsidi) atau akses
/// dicabut. Null = error biasa, pakai pesan lama.
enum SubsidyFailure { exhausted, banned }

/// [usingSubsidy] = gak ada key sendiri waktu error terjadi.
SubsidyFailure? subsidyFailureOf(Object? error, {required bool usingSubsidy}) {
  if (error is! AiException || error.error != AiError.http) return null;
  if (error.detail == aiBannedCode) return SubsidyFailure.banned;
  if (error.status == 402 && usingSubsidy) return SubsidyFailure.exhausted;
  return null;
}

final aiKeyRepositoryProvider = Provider<AiKeyRepository>(
  (ref) => AiKeyRepository(
    ref.watch(apiKeyStoreProvider),
    ref.watch(sessionStoreProvider),
    ref.watch(aiKeyServiceProvider),
  ),
);
