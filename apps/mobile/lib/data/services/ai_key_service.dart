import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backend_client.dart';
import 'session_store.dart';

/// Sisa kuota AI subsidi hari ini (`GET /v1/ai/usage`).
class AiUsage {
  const AiUsage({
    required this.dailyLimitUsd,
    required this.remainingUsd,
    required this.usedTodayUsd,
    required this.resetsAt,
  });

  factory AiUsage.fromJson(Map<String, Object?> json) => AiUsage(
    dailyLimitUsd: (json['dailyLimitUsd']! as num).toDouble(),
    remainingUsd: (json['remainingUsd']! as num).toDouble(),
    usedTodayUsd: (json['usedTodayUsd']! as num).toDouble(),
    resetsAt: DateTime.parse(json['resetsAt']! as String),
  );

  final double dailyLimitUsd;
  final double remainingUsd;
  final double usedTodayUsd;
  final DateTime resetsAt;
}

/// Model yang diizinkan guardrail subsidi (`GET /v1/ai/config`).
class AiSubsidyConfig {
  const AiSubsidyConfig({
    required this.chatModels,
    required this.embeddingModels,
    required this.dailyLimitUsd,
  });

  factory AiSubsidyConfig.fromJson(Map<String, Object?> json) =>
      AiSubsidyConfig(
        chatModels: (json['chatModels']! as List).cast<String>(),
        embeddingModels: (json['embeddingModels']! as List).cast<String>(),
        dailyLimitUsd: (json['dailyLimitUsd']! as num).toDouble(),
      );

  final List<String> chatModels;
  final List<String> embeddingModels;
  final double dailyLimitUsd;
}

/// Panggilan `/v1/ai/*` (docs/backend.md, AI). Kode error `AI_BANNED` = akses
/// AI dicabut.
class AiKeyService {
  AiKeyService(this._client);

  final BackendClient _client;

  /// [rotate] true setelah OpenRouter nolak key subsidi (401).
  Future<SubsidyKey> issueKey(String token, {bool rotate = false}) async {
    final res = await _client.request(
      'POST',
      '/v1/ai/key',
      body: {if (rotate) 'rotate': true},
      token: token,
    );
    final data = res.data!;
    return SubsidyKey(
      key: data['key']! as String,
      expiresAt: DateTime.parse(data['expiresAt']! as String),
    );
  }

  Future<AiUsage> usage(String token) async => AiUsage.fromJson(
    (await _client.request('GET', '/v1/ai/usage', token: token)).data!,
  );

  Future<AiSubsidyConfig> config(String token) async =>
      AiSubsidyConfig.fromJson(
        (await _client.request('GET', '/v1/ai/config', token: token)).data!,
      );
}

final aiKeyServiceProvider = Provider<AiKeyService>(
  (ref) => AiKeyService(ref.watch(backendClientProvider)),
);
