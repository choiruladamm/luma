import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/ai_reply.dart';
import 'backend_client.dart';

/// One daily rollup row for `POST /v2/usage` (docs/backend.md, Usage analytics).
///
/// [feature] is an [AiCallKind] name or `reading`. Null [model], [bookKey], and
/// [keySource] go out as empty strings, because they are part of the row's key
/// on the server.
class UsageRow {
  const UsageRow({
    required this.day,
    required this.feature,
    this.model,
    this.bookKey,
    this.bookTitle,
    this.keySource,
    this.calls = 0,
    this.failed = 0,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.costUsd,
    this.readingSeconds = 0,
  });

  /// Local day as `YYYY-MM-DD`.
  final String day;
  final String feature;
  final String? model;
  final String? bookKey;
  final String? bookTitle;
  final AiKeySource? keySource;
  final int calls;
  final int failed;
  final int promptTokens;
  final int completionTokens;

  /// Null when no call of the row reported a cost.
  final double? costUsd;
  final int readingSeconds;

  Map<String, Object?> toJson() => {
    'day': day,
    'feature': feature,
    'model': model ?? '',
    'book_key': bookKey ?? '',
    'book_title': bookTitle,
    'key_source': keySource?.name ?? '',
    'calls': calls,
    'failed': failed,
    'prompt_tokens': promptTokens,
    'completion_tokens': completionTokens,
    'cost_usd': costUsd,
    'reading_seconds': readingSeconds,
  };
}

/// Calls `POST /v2/usage`. A resend replaces the rows, so retries are safe.
class UsageService {
  UsageService(this._client);

  /// Rows per request, the server's `MAX_USAGE_ROWS`.
  static const maxRows = 500;

  final BackendClient _client;

  /// Sends up to [maxRows] rows and returns how many the server applied.
  Future<int> send(String token, List<UsageRow> rows) async {
    final res = await _client.request(
      'POST',
      '/usage',
      body: {
        'rows': [for (final r in rows) r.toJson()],
      },
      token: token,
    );
    return res.data!['applied']! as int;
  }
}

final usageServiceProvider = Provider<UsageService>(
  (ref) => UsageService(ref.watch(backendClientProvider)),
);
