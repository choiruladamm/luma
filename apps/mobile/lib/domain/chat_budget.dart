import 'dart:convert';

/// Budget satu kiriman Ngobrol (#143): token gabungan input + output lintas
/// semua request, dan tenggat total. Angka reservasi konservatif dipakai
/// sampai usage asli dari provider tersedia; unknown tidak pernah dihitung 0.
const chatQuestionTokens = 2000000;
const chatQuestionDeadline = Duration(minutes: 5);

/// Context window kalau metadata model tidak terbaca: konservatif.
const chatFallbackContextTokens = 128000;

/// Cadangan context untuk system prompt + overhead JSON per request.
const chatContextMargin = 4000;

/// Batas praktis input per request walau context model lebih besar: menjaga
/// latensi prompt processing di bawah tenggat dan kualitas pembacaan.
const chatRequestInputBytes = 240000;

/// Batas embedding terpisah dari chat (dicatat, tidak digabung ke angka chat).
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

/// Metadata model dari provider; `contextTokens` menentukan ukuran batch.
typedef ChatModelInfo = ({String id, int contextTokens, bool fromProvider});

const chatFallbackModelInfo = (
  id: '',
  contextTokens: chatFallbackContextTokens,
  fromProvider: false,
);

class ChatBudgetExceeded extends FormatException {
  const ChatBudgetExceeded(super.message);
}

/// Estimasi konservatif: prosa ≈ 4 byte/token, dihitung 2 byte/token.
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

  /// Pengulangan langkah baca (catatan batch invalid); bukan perbaikan jawaban.
  int batchRetries = 0;
  double? _cost;

  Duration get elapsed => _clock.elapsed;
  Duration get remaining =>
      deadline - elapsed < Duration.zero ? Duration.zero : deadline - elapsed;
  bool get expired => elapsed >= deadline;

  /// Token terpakai: usage asli bila ada, selain itu reservasi tetap dihitung.
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

  /// Biaya provider yang diketahui; null jika ada request tanpa usage.
  double? get cost => unknownUsage ? null : _cost;

  /// Input maksimal (byte) untuk satu request dengan output [maxTokens]:
  /// mengikuti context model, batas praktis, dan sisa budget kiriman.
  int inputBytesFor(int maxTokens) {
    final context = (model.contextTokens - maxTokens - chatContextMargin) * 2;
    final budget = (left - maxTokens) * 2;
    return [
      context,
      budget,
      chatRequestInputBytes,
    ].reduce((a, b) => a < b ? a : b).clamp(0, chatRequestInputBytes);
  }

  /// Reservasi sebelum dispatch. Melempar bila budget/tenggat habis atau
  /// request tidak muat context; tidak pernah menunggu banyak request dulu.
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

  /// Usage asli menggantikan reservasi; null membiarkan reservasi berlaku.
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

  /// Embedding dibatasi dan dicatat terpisah dari token chat.
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

  /// Sisa token masih cukup untuk satu request berukuran [inputBytes]?
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
