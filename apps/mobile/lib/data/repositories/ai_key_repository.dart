import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma/data/services/openrouter_service.dart'
    show OpenRouterService;

import '../../domain/models/ai_reply.dart';
import '../services/ai_key_service.dart';
import '../services/backend_client.dart';
import '../services/api_key_store.dart';
import '../services/session_store.dart';

/// Resolves the OpenRouter key used by AI calls: `key = byok ?? subsidy`
/// (docs/backend.md, AI subsidy). It implements [ApiKeyStore] so existing callers
/// only swap the provider; [write] still stores the BYOK key.
///
/// The subsidy key is fetched from the backend only when needed (missing, close
/// to expiry, or rejected by OpenRouter), so nothing polls.
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

  /// Refetched one day before expiry, matching the server's rotation.
  static const refreshBefore = Duration(days: 1);

  /// Subsidy key OpenRouter just rejected (401); the next read fetches a fresh one.
  String? _rejected;
  Future<String?>? _inFlight;

  @override
  Future<void> write(String key) => _byok.write(key);

  @override
  Future<String?> read() async {
    final own = await _byok.read();
    if (own != null) return own;
    // Several screens can ask at once; share a single backend call.
    return _inFlight ??= _subsidy().whenComplete(() => _inFlight = null);
  }

  /// Called by [OpenRouterService] when OpenRouter replies 401 for [key].
  void markRejected(String key) => _rejected = key;

  /// Returns true when [key] is the subsidy key (not BYOK), to pick the 402 message.
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
      // Free-quota access was revoked: the UI shows the "Akses AI gratis lo dicabut"
      // card (board Kuota AI 12), not "API key belum diisi".
      if (e.code == aiBannedCode) {
        throw const AiException(
          AiError.http,
          status: 403,
          detail: aiBannedCode,
        );
      }
      final usable = stored != null && stored.expiresAt.isAfter(_now());
      if (usable) return stored.key;
      // A session exists but the backend is unreachable: AI screens show a network
      // error instead of asking for a key.
      if (e.code == 'NETWORK') throw const AiException(AiError.network);
      return null;
    } on Object {
      // Secure storage unreadable, etc.: a stored key that hasn't expired is still
      // usable.
      final usable = stored != null && stored.expiresAt.isAfter(_now());
      return usable ? stored.key : null;
    }
  }
}

/// Server code for an account barred from the free quota (docs/backend.md, AI
/// subsidy). Also used as [AiException.detail] so the UI can recognize it.
const aiBannedCode = 'AI_BANNED';

/// Why an AI call failed on the free quota: exhausted (402 with the subsidy key)
/// or access revoked. A null result means an ordinary error with the usual message.
enum SubsidyFailure { exhausted, banned }

/// [usingSubsidy] is true when the user had no key of their own when the error occurred.
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
