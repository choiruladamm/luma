import 'dart:convert';

/// Budget for one Ngobrol send: combined input + output tokens across all
/// requests, and the total deadline. Conservative reservation figures are used
/// until real usage from the provider is available; unknown is never counted as 0.
const chatQuestionTokens = 2000000;
const chatQuestionDeadline = Duration(minutes: 5);

/// Context window when the model metadata can't be read: conservative.
const chatFallbackContextTokens = 128000;

/// Context reserved for the system prompt + JSON overhead per request.
const chatContextMargin = 4000;

/// Practical per-request input cap even when the model context is larger: keeps
/// prompt-processing latency under the deadline and reading quality up.
const chatRequestInputBytes = 240000;

/// Embedding limit, separate from chat (recorded, not merged into the chat figures).
const chatEmbeddingRequests = 90;
const chatEmbeddingBytes = 3200000;

typedef ChatUsage = ({int promptTokens, int completionTokens, double? cost});

ChatUsage? parseChatUsage(Object? value) {
  if (value is! Map) return null;
  final prompt = value['prompt_tokens'],
      completion = value['completion_tokens'];
  if (prompt is! int || completion is! int || prompt < 0 || completion < 0) {
    return null;
  }
  final cost = value['cost'];
  return (
    promptTokens: prompt,
    completionTokens: completion,
    cost: cost is num && cost.isFinite && cost >= 0 ? cost.toDouble() : null,
  );
}

/// Model metadata from the provider; `contextTokens` decides the batch size.
typedef ChatModelInfo = ({String id, int contextTokens, bool fromProvider});

const chatFallbackModelInfo = (
  id: '',
  contextTokens: chatFallbackContextTokens,
  fromProvider: false,
);

class ChatBudgetExceeded extends FormatException {
  const ChatBudgetExceeded(super.message);
}

/// Conservative estimate: prose ≈ 4 bytes/token, counted as 2 bytes/token.
int chatEstimateTokens(String text) => (utf8.encode(text).length + 1) ~/ 2;

class ChatBudget {
  ChatBudget({
    required this.model,
    this.tokens = chatQuestionTokens,
    this.deadline = chatQuestionDeadline,
    Stopwatch? clock,
  }) : _clock = clock ?? (Stopwatch()..start());

  final ChatModelInfo model;
  final int tokens;
  final Duration deadline;
  final Stopwatch _clock;
  final _held = <int>[];
  final _settled = <int, ChatUsage>{};
  int completions = 0, embeddings = 0, embeddingBytes = 0, repairs = 0;

  /// Retries of the reading step (invalid batch notes); not answer repair.
  int batchRetries = 0;
  double? _cost;

  Duration get elapsed => _clock.elapsed;
  Duration get remaining =>
      deadline - elapsed < Duration.zero ? Duration.zero : deadline - elapsed;
  bool get expired => elapsed >= deadline;

  /// Tokens used: real usage when present, otherwise the reservation still counts.
  int get used {
    var sum = 0;
    for (final (i, held) in _held.indexed) {
      final u = _settled[i];
      sum += u == null ? held : u.promptTokens + u.completionTokens;
    }
    return sum;
  }

  int get left => tokens - used < 0 ? 0 : tokens - used;
  bool get unknownUsage => _held.length > _settled.length;

  /// Known provider cost; null if any request had no usage.
  double? get cost => unknownUsage ? null : _cost;

  /// Summed completion usage; null if any request had no usage. Embeddings are
  /// not included.
  ChatUsage? get usage {
    if (unknownUsage || _settled.isEmpty) return null;
    var prompt = 0, completion = 0;
    for (final u in _settled.values) {
      prompt += u.promptTokens;
      completion += u.completionTokens;
    }
    return (promptTokens: prompt, completionTokens: completion, cost: cost);
  }

  /// Maximum input (bytes) for one request with output [maxTokens]: bounded by
  /// the model context, the practical cap, and the send's remaining budget.
  int inputBytesFor(int maxTokens) {
    final context = (model.contextTokens - maxTokens - chatContextMargin) * 2;
    final budget = (left - maxTokens) * 2;
    return [
      context,
      budget,
      chatRequestInputBytes,
    ].reduce((a, b) => a < b ? a : b).clamp(0, chatRequestInputBytes);
  }

  /// Reservation before dispatch. Throws when the budget or deadline is exhausted
  /// or the request doesn't fit the context; never waits on many requests first.
  int reserveCompletion(String system, String user, int maxTokens) {
    final input = chatEstimateTokens(system) + chatEstimateTokens(user);
    if (expired) throw const ChatBudgetExceeded('Tenggat kiriman habis');
    if (input + maxTokens + chatContextMargin > model.contextTokens) {
      throw const ChatBudgetExceeded('Request melebihi context model');
    }
    if (input + maxTokens > left) {
      throw const ChatBudgetExceeded('Budget token kiriman habis');
    }
    completions++;
    _held.add(input + maxTokens);
    return _held.length - 1;
  }

  /// Real usage replaces the reservation; null keeps the reservation.
  void settle(int reservation, ChatUsage? usage) {
    if (reservation < 0 ||
        reservation >= _held.length ||
        _settled.containsKey(reservation)) {
      throw ArgumentError.value(reservation, 'reservation');
    }
    if (usage == null) return;
    _settled[reservation] = usage;
    if (usage.cost != null) _cost = (_cost ?? 0) + usage.cost!;
  }

  /// Embeddings are limited and recorded separately from chat tokens.
  void reserveEmbedding(List<String> inputs) {
    if (expired) throw const ChatBudgetExceeded('Tenggat kiriman habis');
    embeddings++;
    embeddingBytes += inputs.fold(0, (n, s) => n + utf8.encode(s).length);
    if (embeddings > chatEmbeddingRequests ||
        embeddingBytes > chatEmbeddingBytes) {
      throw const ChatBudgetExceeded(
        'Budget index/query habis; lanjutkan secara eksplisit',
      );
    }
  }

  /// Are the remaining tokens enough for one request of [inputBytes]?
  bool fits(int inputBytes, int maxTokens) =>
      !expired && (inputBytes + 1) ~/ 2 + maxTokens <= left;

  Map<String, Object?> get report => {
    'used': used,
    'left': left,
    'completions': completions,
    'embeddings': embeddings,
    'embeddingBytes': embeddingBytes,
    'repairs': repairs,
    'batchRetries': batchRetries,
    'unknownUsage': unknownUsage,
    'cost': cost,
    'elapsedMs': elapsed.inMilliseconds,
    'contextTokens': model.contextTokens,
    'contextFromProvider': model.fromProvider,
  };
}
