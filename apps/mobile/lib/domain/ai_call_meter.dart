import 'chat_budget.dart';

/// Usage and latency of one logged AI call (one `ai_calls` row), which can span
/// several provider requests (retries, repairs, the non-streaming fallback).
class AiCallMeter {
  AiCallMeter() : _clock = Stopwatch()..start();

  final Stopwatch _clock;
  Duration? _firstToken;
  int? _prompt, _completion;
  double? _cost;

  /// Adds one request's reported usage.
  // ponytail: a request that reports no usage is simply not counted, so a
  // call mixing reported and unreported requests undercounts. Track request
  // counts if that mix shows up in the stats.
  void add(ChatUsage usage) {
    _prompt = (_prompt ?? 0) + usage.promptTokens;
    _completion = (_completion ?? 0) + usage.completionTokens;
    if (usage.cost != null) _cost = (_cost ?? 0) + usage.cost!;
  }

  /// Marks the first visible token; later calls keep the first time.
  void firstToken() => _firstToken ??= _clock.elapsed;

  /// Summed usage; null when no request reported any.
  ChatUsage? get usage => _prompt == null
      ? null
      : (promptTokens: _prompt!, completionTokens: _completion!, cost: _cost);

  int? get firstTokenMs => _firstToken?.inMilliseconds;
  int get totalMs => _clock.elapsed.inMilliseconds;
}
