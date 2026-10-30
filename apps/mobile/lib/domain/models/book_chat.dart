import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'ai_reply.dart';

/// Revision isi/urutan; perubahan metadata tidak membuat snapshot baru.
typedef ChatBookRef = ({int bookId, int contentRevision});
typedef ChatParagraphRef = ({int chapterId, int paragraphIndex});
typedef ChatReadingPosition = ({
  int chapterId,
  int paragraphIndex,
  double paragraphOffset,
});
typedef ChatScrollAnchor = ({int turnId, int blockIndex, double alignment});
typedef ChatAttemptRef = ({
  int sessionId,
  int turnId,
  int attempt,
  ChatBookRef book,
});
typedef ChatParagraph = ({
  ChatBookRef book,
  int chapterId,
  int paragraphIndex,
  String text,
});

bool chatValidUnicode(String text) =>
    !text.runes.any((r) => r >= 0xd800 && r <= 0xdfff);

String chatTextHash(String text) =>
    sha256.convert(utf8.encode(text)).toString();

class ChatSession {
  const ChatSession({
    required this.id,
    required this.book,
    required this.title,
    required this.manualTitle,
    required this.createdAt,
    required this.updatedAt,
    this.lastOpenedAt,
    this.scrollAnchor,
    this.preview,
    this.invalid = false,
  });

  final int id;
  final ChatBookRef book;
  final String title;
  final bool manualTitle;
  final DateTime createdAt, updatedAt;
  final DateTime? lastOpenedAt;
  final ChatScrollAnchor? scrollAnchor;

  /// Pertanyaan terakhir sesi ini, bukan jawaban atau konteks lintas sesi.
  final String? preview;
  final bool invalid;

  bool isArchived(ChatBookRef current) => book != current;
}

/// Offset UTF-16, end eksklusif. Hash selalu seluruh paragraf, snapshot hanya range.
class SourceAnchor {
  const SourceAnchor({
    required this.book,
    required this.chapterId,
    required this.paragraphIndex,
    required this.start,
    required this.end,
    required this.paragraphHash,
    required this.snapshot,
  });

  final ChatBookRef book;
  final int chapterId, paragraphIndex, start, end;
  final String paragraphHash, snapshot;
  ChatParagraphRef get paragraph =>
      (chapterId: chapterId, paragraphIndex: paragraphIndex);

  void validate(ChatParagraph current, ChatBookRef currentBook) {
    if (book.bookId <= 0 ||
        book.contentRevision <= 0 ||
        book != currentBook ||
        current.book != book ||
        chapterId <= 0 ||
        current.chapterId != chapterId ||
        paragraphIndex < 0 ||
        current.paragraphIndex != paragraphIndex ||
        !chatValidUnicode(current.text) ||
        start < 0 ||
        end <= start ||
        end > current.text.length ||
        !_boundary(current.text, start) ||
        !_boundary(current.text, end) ||
        paragraphHash != chatTextHash(current.text) ||
        current.text.substring(start, end) != snapshot) {
      throw const FormatException('Sumber buku berubah atau tidak cocok');
    }
  }
}

bool _boundary(String text, int offset) =>
    offset == text.length ||
    !(text.codeUnitAt(offset) >= 0xdc00 && text.codeUnitAt(offset) <= 0xdfff);

class ChatSource {
  ChatSource({
    required this.id,
    required this.chapterTitle,
    required List<SourceAnchor> anchors,
  }) : anchors = List.unmodifiable(anchors) {
    if (anchors.isEmpty) throw const FormatException('Sumber kosong');
  }

  final String id, chapterTitle;
  final List<SourceAnchor> anchors;
  String get text => anchors.map((a) => a.snapshot).join('\n\n');
}

class ChatQuote {
  ChatQuote({
    required List<SourceAnchor> anchors,
    this.translation,
    this.chapterTitle,
  }) : anchors = List.unmodifiable(anchors) {
    if (anchors.isEmpty) throw const FormatException('Kutipan kosong');
  }

  final List<SourceAnchor> anchors;

  /// Pendamping UI saja; bukan bukti dan tidak dikirim sebagai selectedQuote.
  final String? translation, chapterTitle;
  String get text => anchors.map((a) => a.snapshot).join('\n\n');
}

enum ChatAnswerStatus {
  answered,
  partial,
  notFound,
  clarify,
  offTopic;

  String get wireValue => switch (this) {
    notFound => 'not_found',
    clarify => 'clarify',
    offTopic => 'off_topic',
    _ => name,
  };

  static ChatAnswerStatus parse(Object? value) => switch (value) {
    'answered' => answered,
    'partial' => partial,
    'not_found' => notFound,
    'clarify' => clarify,
    'off_topic' => offTopic,
    _ => throw const FormatException('Status jawaban tidak dikenal'),
  };
}

enum ChatAnswerKind {
  book,
  interpretation,
  external,
  conversation;

  static ChatAnswerKind parse(Object? value) => switch (value) {
    'book' => book,
    'interpretation' => interpretation,
    'external' => external,
    'conversation' => conversation,
    _ => throw const FormatException('Jenis paragraf tidak dikenal'),
  };
}

class ChatAnswerBlock {
  ChatAnswerBlock({
    required this.text,
    required List<ChatSource> sources,
    this.kind = ChatAnswerKind.book,
  }) : sources = List.unmodifiable(sources);
  final String text;
  final List<ChatSource> sources;
  final ChatAnswerKind kind;
}

class ChatAnswer {
  ChatAnswer({
    required this.status,
    required List<ChatAnswerBlock> blocks,
    this.formatVersion = 1,
  }) : blocks = List.unmodifiable(blocks) {
    if (![1, 2].contains(formatVersion) ||
        formatVersion == 1 &&
            (blocks.length > 2 ||
                (status == ChatAnswerStatus.notFound) != blocks.isEmpty ||
                status == ChatAnswerStatus.clarify ||
                status == ChatAnswerStatus.offTopic) ||
        formatVersion == 2 &&
            (blocks.isEmpty ||
                blocks.length > 32 ||
                status == ChatAnswerStatus.notFound) ||
        blocks.any(
          (b) =>
              b.text.trim().isEmpty ||
              !chatValidUnicode(b.text) ||
              b.kind == ChatAnswerKind.book && b.sources.isEmpty ||
              formatVersion == 1 && b.kind != ChatAnswerKind.book ||
              (b.kind == ChatAnswerKind.external ||
                      b.kind == ChatAnswerKind.conversation) &&
                  b.sources.isNotEmpty,
        )) {
      throw const FormatException('Jawaban tidak konsisten');
    }
  }
  final ChatAnswerStatus status;
  final List<ChatAnswerBlock> blocks;
  final int formatVersion;

  String get note {
    if (formatVersion == 2) return '';
    return switch (status) {
      ChatAnswerStatus.answered => '',
      ChatAnswerStatus.partial =>
        'Sebagian pertanyaan belum punya bukti yang cukup di sumber ini.',
      ChatAnswerStatus.notFound => 'Belum ada sumber yang cukup untuk menjawab itu. Coba tunjukkan kutipan atau perjelas pertanyaannya.',
      ChatAnswerStatus.clarify || ChatAnswerStatus.offTopic => '',
    };
  }
}

enum ChatPhase {
  preparing,
  retrieving,
  waiting,
  writing,
  slow,
  done,
  failed,
  cut,
  stopped,
  interrupted;

  bool get isRunning => switch (this) {
    preparing || retrieving || waiting || writing || slow => true,
    _ => false,
  };

  /// Nilai backup rusak tidak boleh memulai request atau menjadi history terpercaya.
  static ChatPhase restore(Object? value) => ChatPhase.values.firstWhere(
    (p) => p.name == value,
    orElse: () => interrupted,
  );
}

class ChatTurn {
  const ChatTurn({
    required this.id,
    required this.sessionId,
    required this.book,
    required this.sequence,
    required this.question,
    required this.createdAt,
    required this.updatedAt,
    required this.phase,
    required this.model,
    required this.promptVersion,
    this.attempt = 1,
    this.quote,
    this.draft = '',
    this.preview = const [],
    this.answer,
    this.error,
    this.httpStatus,
    this.exploration,
  });

  final int id, sessionId, sequence, attempt, promptVersion;
  final ChatBookRef book;
  final String question, model, draft;
  final String? exploration;
  final ChatQuote? quote;
  final DateTime createdAt, updatedAt;
  final ChatPhase phase;
  final ChatAnswer? answer;
  final List<ChatAnswerBlock> preview;
  final AiError? error;
  final int? httpStatus;

  ChatAttemptRef get attemptRef =>
      (sessionId: sessionId, turnId: id, attempt: attempt, book: book);
  bool accepts(ChatAttemptRef ref, ChatBookRef current) =>
      phase.isRunning && current == book && ref == attemptRef;
  bool get trustedHistory =>
      phase == ChatPhase.done && error == null && answer != null;

  ChatTurn interrupt(DateTime at, {bool cancelled = false}) {
    if (!phase.isRunning) return this;
    return _attemptState(
      at: at,
      phase: cancelled ? ChatPhase.stopped : ChatPhase.interrupted,
      attempt: attempt,
      draft: draft,
      model: model,
      promptVersion: promptVersion,
    );
  }

  ChatTurn retry({
    required ChatBookRef current,
    required bool isLatest,
    required DateTime at,
    required String model,
    required int promptVersion,
  }) {
    if (current != book ||
        !isLatest ||
        ![
          ChatPhase.failed,
          ChatPhase.cut,
          ChatPhase.stopped,
          ChatPhase.interrupted,
        ].contains(phase)) {
      throw StateError('Cuma turn terakhir yang terputus bisa dicoba lagi');
    }
    return _attemptState(
      at: at,
      phase: ChatPhase.preparing,
      attempt: attempt + 1,
      draft: '',
      model: model,
      promptVersion: promptVersion,
    );
  }

  ChatTurn _attemptState({
    required DateTime at,
    required ChatPhase phase,
    required int attempt,
    required String draft,
    required String model,
    required int promptVersion,
  }) => ChatTurn(
    id: id,
    sessionId: sessionId,
    book: book,
    sequence: sequence,
    question: question,
    createdAt: createdAt,
    updatedAt: at,
    phase: phase,
    attempt: attempt,
    quote: quote,
    draft: draft,
    model: model,
    promptVersion: promptVersion,
    exploration: model == this.model && promptVersion == this.promptVersion
        ? exploration
        : null,
  );
}

enum ChatSearchStrategy { specific, crossChapter, global, correction, offTopic }

class ChatQueryPlan {
  const ChatQueryPlan({
    required this.englishQuery,
    required this.needsClarification,
    this.strategy = ChatSearchStrategy.specific,
    this.queries = const [],
  });
  final String englishQuery;
  final bool needsClarification;
  final ChatSearchStrategy strategy;
  final List<String> queries;
}

enum ChatEmbeddingModel {
  qwen8b('qwen/qwen3-embedding-8b', 4096),
  openaiLarge('openai/text-embedding-3-large', 3072);

  const ChatEmbeddingModel(this.id, this.dimensions);
  final String id;
  final int dimensions;
}

/// Identik per nilai; model/dimensi/template/revision tidak pernah tercampur.
typedef ChatIndexKey = ({
  ChatBookRef book,
  int parserVersion,
  int chunkPolicyVersion,
  ChatEmbeddingModel embedding,
  int queryTemplateVersion,
});

enum ChatLaunchOrigin { reader, meaning, breakdown }

class ChatLaunchContext {
  ChatLaunchContext({
    required this.book,
    required this.returnPosition,
    this.origin = ChatLaunchOrigin.reader,
    this.quote,
  }) {
    if (origin != ChatLaunchOrigin.reader && quote == null ||
        quote != null && quote!.anchors.any((a) => a.book != book)) {
      throw const FormatException('Kutipan entry tidak cocok');
    }
  }
  final ChatBookRef book;
  final ChatReadingPosition returnPosition;
  final ChatLaunchOrigin origin;
  final ChatQuote? quote;
  bool get startsNewSession => quote != null;
}

/// Only IDs cross the route boundary; every visit resolves the frozen evidence.
typedef ChatSourceRef = ({
  int bookId,
  int sessionId,
  int turnId,
  int attempt,
  String sourceId,
});

class ChatSourceLocation {
  const ChatSourceLocation({
    required this.source,
    required this.available,
    this.generation,
    this.positionLabel,
    this.before,
    this.after,
  });
  final String? positionLabel, before, after;
  final ChatSource source;
  final bool available;

  /// Repository lifetime changes across restore, even if numeric IDs match.
  final Object? generation;
}

class SourceVisitRequest {
  const SourceVisitRequest({
    required this.sessionId,
    required this.turnId,
    required this.anchor,
    required this.returnPosition,
    required this.chatPosition,
  });
  final int sessionId, turnId;
  final SourceAnchor anchor;
  final ChatReadingPosition returnPosition;
  final ChatScrollAnchor chatPosition;

  /// Resolver #122 wajib memanggil ini sebelum jump; kunjungan tidak menulis progres.
  void validate({
    required ChatSession session,
    required ChatTurn turn,
    required ChatParagraph paragraph,
    required ChatBookRef current,
  }) {
    if (session.id != sessionId ||
        turn.id != turnId ||
        turn.sessionId != sessionId ||
        session.book != current ||
        turn.book != current ||
        anchor.book != current) {
      throw const FormatException(
        'Kunjungan sumber dari sesi berbeda atau arsip',
      );
    }
    anchor.validate(paragraph, current);
  }
}

/// Null means return to the immediate origin; reading unwinds its overlays.
enum ReaderReturn { reading }
