import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/ai_key_repository.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/services/ai_key_service.dart';
import '../../../../data/services/api_key_store.dart';
import '../../../../data/services/backend_client.dart';
import '../../../../domain/models/ai_model.dart';

/// Dari mana key AI: kuota gratis Luma atau key OpenRouter sendiri
/// (docs/backend.md, AI). Ada key sendiri = key sendiri.
enum AiSource { subsidy, own }

final aiSourceProvider = FutureProvider<AiSource>((ref) async {
  final own = await ref.watch(apiKeyStoreProvider).read();
  return own == null ? AiSource.subsidy : AiSource.own;
});

/// Biaya rata-rata satu tap Artinya (board Kuota AI: $0,02 ≈ 30–50 tap).
// shortcut: konstanta, `ai_calls` belum diisi; hitung dari biaya asli kalau
// log biaya udah jalan.
const estimatedTapCostUsd = 0.0005;

/// Sisa kuota gratis hari ini (board Kuota AI 01).
class QuotaState {
  const QuotaState({this.usage, this.banned = false});

  final AiUsage? usage;

  /// Akun diblokir dari kuota gratis.
  final bool banned;

  /// 0–100, dibulatkan.
  int get percent {
    final u = usage;
    if (u == null || u.dailyLimitUsd <= 0) return 0;
    return (u.remainingUsd / u.dailyLimitUsd * 100).clamp(0, 100).round();
  }

  /// Segmen terisi dari 10.
  int get segments => (percent / 10).ceil().clamp(0, 10);

  /// "± N tap lagi".
  int get tapsLeft =>
      ((usage?.remainingUsd ?? 0) / estimatedTapCostUsd).floor();

  /// Sisa < 20% (board: "Hampir abis").
  bool get low => percent > 0 && percent < 20;

  bool get exhausted => usage != null && percent == 0;
}

/// Kuota dicek paling sering sejam sekali (aturan free tier, docs/backend.md):
/// provider hidup sepanjang app, [refresh] cuma manggil server kalau hasil
/// terakhir udah basi atau [force].
class AiQuotaController extends AsyncNotifier<QuotaState> {
  static const cacheFor = Duration(hours: 1);

  DateTime? _fetchedAt;

  DateTime Function() get _now => ref.read(quotaClockProvider);

  @override
  Future<QuotaState> build() => _fetch();

  Future<void> refresh({bool force = false}) async {
    final at = _fetchedAt;
    if (!force && at != null && _now().difference(at) < cacheFor) return;
    state = const AsyncLoading<QuotaState>();
    state = await AsyncValue.guard(_fetch);
  }

  Future<QuotaState> _fetch() async {
    final token = await ref.read(authRepositoryProvider).token();
    if (token == null) {
      throw const BackendException(code: 'UNAUTHORIZED', message: 'no session');
    }
    try {
      final usage = await ref.read(aiKeyServiceProvider).usage(token);
      _fetchedAt = _now();
      return QuotaState(usage: usage);
    } on BackendException catch (e) {
      if (e.code != aiBannedCode) rethrow;
      _fetchedAt = _now();
      return const QuotaState(banned: true);
    }
  }
}

final quotaClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final aiQuotaProvider = AsyncNotifierProvider<AiQuotaController, QuotaState>(
  AiQuotaController.new,
);

/// Model yang boleh dipilih di mode kuota gratis (`/v1/ai/config`, cache
/// sepanjang app). Gagal / offline → daftar cadangan [subsidyModelIds].
final subsidyModelsProvider = FutureProvider<List<String>>((ref) async {
  final token = await ref.watch(authRepositoryProvider).token();
  if (token == null) return subsidyModelIds;
  try {
    final config = await ref.watch(aiKeyServiceProvider).config(token);
    return config.chatModels.isEmpty ? subsidyModelIds : config.chatModels;
  } on BackendException {
    return subsidyModelIds;
  }
});
