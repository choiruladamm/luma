import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backend_client.dart';
import 'session_store.dart';

/// Represents today’s remaining subsidized AI quota (`GET /v2/ai/usage`).
class AiUsage {
  const AiUsage({
    required this.dailyLimitUsd,
    required this.remainingUsd,
    required this.usedTodayUsd,
    required this.resetsAt,
  });

  factory AiUsage.fromJson(Map<String, Object?> json) => AiUsage(
    dailyLimitUsd: (json['daily_limit_usd']! as num).toDouble(),
    remainingUsd: (json['remaining_usd']! as num).toDouble(),
    usedTodayUsd: (json['used_today_usd']! as num).toDouble(),
    resetsAt: DateTime.parse(json['resets_at']! as String),
  );

  final double dailyLimitUsd;
  final double remainingUsd;
  final double usedTodayUsd;
  final DateTime resetsAt;
}

/// Represents a model allowed by the subsidy guardrail (`GET /v2/ai/config`).
class AiSubsidyConfig {
  const AiSubsidyConfig({
    required this.chatModels,
    required this.embeddingModels,
    required this.dailyLimitUsd,
  });

  factory AiSubsidyConfig.fromJson(Map<String, Object?> json) =>
      AiSubsidyConfig(
        chatModels: (json['chat_models']! as List).cast<String>(),
        embeddingModels: (json['embedding_models']! as List).cast<String>(),
        dailyLimitUsd: (json['daily_limit_usd']! as num).toDouble(),
      );

  final List<String> chatModels;
  final List<String> embeddingModels;
  final double dailyLimitUsd;
}

/// Calls `/v2/ai/*` (docs/backend.md, AI subsidy).
/// The `AI_BANNED` error means AI access was revoked.
class AiKeyService {
  AiKeyService(this._client);

  final BackendClient _client;

  /// Sets [rotate] after OpenRouter rejects the subsidized key (401).
  Future<SubsidyKey> issueKey(String token, {bool rotate = false}) async {
    final res = await _client.request(
      'POST',
      '/ai/key',
      body: {if (rotate) 'rotate': true},
      token: token,
    );
    final data = res.data!;
    return SubsidyKey(
      key: data['key']! as String,
      expiresAt: DateTime.parse(data['expires_at']! as String),
    );
  }

  Future<AiUsage> usage(String token) async => AiUsage.fromJson(
    (await _client.request('GET', '/ai/usage', token: token)).data!,
  );

  Future<AiSubsidyConfig> config(String token) async =>
      AiSubsidyConfig.fromJson(
        (await _client.request('GET', '/ai/config', token: token)).data!,
      );
}

final aiKeyServiceProvider = Provider<AiKeyService>(
  (ref) => AiKeyService(ref.watch(backendClientProvider)),
);
