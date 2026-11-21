/// One paragraph group: chapter (stable id) + `groupIndex`. A record, so
/// `==`/`hashCode` are by value, safe as a provider family key.
typedef GroupRef = ({int chapterId, int groupIndex});

/// The LLM answer for one group (docs/llm.md).
class AiReply {
  const AiReply({required this.translations, required this.meaning});

  /// One translation per TARGET paragraph, in order.
  final List<String> translations;

  /// Explanation of the meaning of the whole group.
  final String meaning;
}

/// Feature that made an `ai_calls` row: Artinya, Bedahin, Ngobrolin buku.
///
/// TODO(#104): add a Recap value.
enum AiCallKind { group, breakdown, chat }

/// Whose OpenRouter key paid for an `ai_calls` row.
enum AiKeySource { own, subsidy }

enum AiError {
  /// The API key isn't set: the API isn't called.
  noApiKey,

  /// Took longer than ±30 seconds.
  timeout,

  /// Can't reach OpenRouter (offline, DNS, etc.).
  network,

  /// HTTP status isn't 2xx; see [AiException.status].
  http,

  /// Not the requested JSON, or the translation count doesn't match.
  invalidResponse,
}

class AiException implements Exception {
  const AiException(this.error, {this.status, this.detail});

  final AiError error;

  /// HTTP status for [AiError.http] (401 = key rejected, 402 = out of balance).
  final int? status;
  final String? detail;

  @override
  String toString() =>
      'AiException(${error.name}${status == null ? '' : ' $status'}'
      '${detail == null ? '' : ': $detail'})';
}

/// Stage of one group's streamed answer (board "Artinya streaming · perilaku").
enum AiPhase {
  /// 1 · Waiting for the first token.
  waiting,

  /// 2 · Writing the translation, paragraphs arriving in order.
  translating,

  /// 3 · Translation complete, writing the meaning.
  meaning,

  /// 4 · Complete, valid, cached.
  done,

  /// 5 · 15 seconds without a token. The request keeps running.
  slow,

  /// 6 · Dropped / stalled midway; what already arrived stays.
  cut,

  /// Failed before any token (no key, 30-second timeout, HTTP, etc.).
  failed,
}
