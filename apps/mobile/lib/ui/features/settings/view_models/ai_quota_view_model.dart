import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/ai_key_repository.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/services/ai_key_service.dart';
import '../../../../data/services/api_key_store.dart';
import '../../../../data/services/backend_client.dart';
import '../../../../domain/models/ai_model.dart';

/// Where the AI key comes from: Luma's free quota or the user's own OpenRouter
/// key (docs/backend.md, AI subsidy). Having your own key = own key.
enum AiSource { subsidy, own }

final aiSourceProvider = FutureProvider<AiSource>((ref) async {
  final own = await ref.watch(apiKeyStoreProvider).read();
  return own == null ? AiSource.subsidy : AiSource.own;
});

/// Average cost of one Artinya tap (board Kuota AI: $0.02 ≈ 30–50 taps).
// ponytail: constant, `ai_calls` isn't populated yet; compute from the real
// cost once cost logging runs.
const estimatedTapCostUsd = 0.0005;

/// Remaining free quota today (board Kuota AI 01).
class QuotaState {
  const QuotaState({this.usage, this.banned = false});

  final AiUsage? usage;

  /// Account is blocked from the free quota.
  final bool banned;

  /// 0–100, rounded.
  int get percent {
    final u = usage;
    if (u == null || u.dailyLimitUsd <= 0) return 0;
    return (u.remainingUsd / u.dailyLimitUsd * 100).clamp(0, 100).round();
  }

  /// Filled segments out of 10.
  int get segments => (percent / 10).ceil().clamp(0, 10);

  /// "± N tap lagi".
  int get tapsLeft =>
      ((usage?.remainingUsd ?? 0) / estimatedTapCostUsd).floor();

  /// Remaining < 20% (board: "Hampir abis").
  bool get low => percent > 0 && percent < 20;

  bool get exhausted => usage != null && percent == 0;
}

/// The quota is checked at most once an hour (docs/budgets.md, Client request
/// policy): the provider lives for the whole app, [refresh] only calls the
/// server when the last result is stale or `force`.
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

/// Models selectable in free quota mode (`/v1/ai/config`, cached for the whole
/// app). Failure / offline → fallback list [subsidyModelIds].
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
