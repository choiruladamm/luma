import 'dart:convert';

/// Langkah AI: the trail of what the app did during one Ngobrol attempt (plan,
/// cache, read, search, stop, repair, answer). Recorded without extra requests,
/// stored once in `chat_turns.steps`.
enum ChatStepKind {
  plan,
  cache,
  read,
  search,
  skip,
  repair,
  retry,
  stop,
  answer,
}

enum ChatStepStatus { done, running, skipped }

const chatStepsMax = 400;
const chatStepTextMax = 300;

class ChatStep {
  const ChatStep({
    required this.kind,
    required this.label,
    this.detail,
    this.status = ChatStepStatus.done,
  });

  /// Row text in the list ("Baca Book I › III: Of Providence").
  final String label;

  /// Muted note after the label (" · 4 catatan").
  final String? detail;
  final ChatStepKind kind;
  final ChatStepStatus status;

  ChatStep.plan(String what, {String? detail})
    : this(kind: ChatStepKind.plan, label: 'Rencana: $what', detail: detail);
  ChatStep.cache(int chapters)
    : this(
        kind: ChatStepKind.cache,
        label: 'Pakai catatan tersimpan',
        detail: '$chapters bab',
      );
  ChatStep.read(
    String chapter, {
    String? detail,
    ChatStepStatus status = ChatStepStatus.done,
  }) : this(
         kind: ChatStepKind.read,
         label: 'Baca $chapter',
         detail: detail,
         status: status,
       );
  ChatStep.search(
    String query, {
    String? detail,
    ChatStepStatus status = ChatStepStatus.done,
  }) : this(
         kind: ChatStepKind.search,
         label: 'Cari: $query',
         detail: detail,
         status: status,
       );
  ChatStep.skip(String chapters)
    : this(
        kind: ChatStepKind.skip,
        label: 'Dilewati: $chapters',
        detail: 'bukan isi',
        status: ChatStepStatus.skipped,
      );
  ChatStep.repair(int attempt, int max)
    : this(
        kind: ChatStepKind.repair,
        label: 'Benerin format jawaban ($attempt/$max)',
      );
  ChatStep.retry(String chapter)
    : this(
        kind: ChatStepKind.retry,
        label: 'Ulang baca $chapter',
        detail: 'catatan ditolak',
      );
  ChatStep.stop(String reason, {String? detail})
    : this(kind: ChatStepKind.stop, label: 'Berhenti: $reason', detail: detail);
  ChatStep.answer({ChatStepStatus status = ChatStepStatus.done})
    : this(kind: ChatStepKind.answer, label: 'Jawaban', status: status);

  ChatStep withStatus(ChatStepStatus status) =>
      ChatStep(kind: kind, label: label, detail: detail, status: status);

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'label': label,
    if (detail != null) 'detail': detail,
    'status': status.name,
  };

  @override
  bool operator ==(Object other) =>
      other is ChatStep &&
      other.kind == kind &&
      other.label == label &&
      other.detail == detail &&
      other.status == status;
  @override
  int get hashCode => Object.hash(kind, label, detail, status);
  @override
  String toString() =>
      'ChatStep(${kind.name}, $label, $detail, ${status.name})';
}

/// Checkpoint stop reason → step label.
String chatStopLabel(String reason) => switch (reason) {
  'user' => 'Jawab sekarang',
  'deadline' => 'waktu habis',
  'budget' => 'jatah token habis',
  'stagnant' => 'pencarian mandek',
  _ => reason,
};

/// Adds [step] to [steps] following the display rules: a `running` step is always
/// last and is replaced by the next running one; a finished step with the same
/// kind+label completes that running step, any other finished step goes in front
/// of it.
List<ChatStep> chatAppendStep(List<ChatStep> steps, ChatStep step) {
  final trailing = steps.isNotEmpty && steps.last.status.isRunning;
  final done = trailing ? steps.sublist(0, steps.length - 1) : steps;
  if (step.status.isRunning) return [...done, step];
  final resolves =
      trailing &&
      steps.last.kind == step.kind &&
      steps.last.label == step.label;
  return [...done, step, if (trailing && !resolves) steps.last];
}

/// The attempt ended without an answer: steps still running are recorded as skipped.
List<ChatStep> chatSettleSteps(List<ChatStep> steps) =>
    steps.isNotEmpty && steps.last.status.isRunning
    ? [
        ...steps.take(steps.length - 1),
        steps.last.withStatus(ChatStepStatus.skipped),
      ]
    : steps;

extension ChatStepStatusX on ChatStepStatus {
  bool get isRunning => this == ChatStepStatus.running;
}

String encodeChatSteps(List<ChatStep> steps) =>
    jsonEncode([for (final s in steps) s.toJson()]);

/// Strict decode: kind/status must be known, labels non-empty, count and length
/// bounded. Throws [FormatException] for corrupt values.
List<ChatStep> decodeChatSteps(String raw) {
  final value = jsonDecode(raw);
  if (value is! List || value.length > chatStepsMax) {
    throw const FormatException('Langkah tidak valid');
  }
  return [
    for (final item in value)
      if (item is Map)
        _step(item)
      else
        throw const FormatException('Langkah tidak valid'),
  ];
}

ChatStep _step(Map<Object?, Object?> item) {
  final kind = ChatStepKind.values.where((k) => k.name == item['kind']);
  final status = ChatStepStatus.values.where((s) => s.name == item['status']);
  final label = item['label'], detail = item['detail'];
  if (kind.isEmpty ||
      status.isEmpty ||
      label is! String ||
      label.trim().isEmpty ||
      label.length > chatStepTextMax ||
      detail != null &&
          (detail is! String || detail.length > chatStepTextMax)) {
    throw const FormatException('Langkah tidak valid');
  }
  return ChatStep(
    kind: kind.single,
    label: label,
    detail: detail as String?,
    status: status.single,
  );
}
