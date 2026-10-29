import 'dart:convert';

import '../../domain/chat_prompt.dart';
import '../../domain/models/ai_reply.dart';
import '../../domain/models/book_chat.dart';
import '../database/app_database.dart';

// Decoder arsip memeriksa struktur/ownership, bukan keberadaan paragraf terbaru.
// Validasi hash/range terhadap buku aktif dilakukan lagi sebelum prompt/jump.
class ChatSnapshot {
  static Object? json(String raw, {int maxBytes = chatSelectorBytes}) {
    text(raw, maxBytes: maxBytes);
    return jsonDecode(raw);
  }

  static String text(Object? value, {int maxBytes = chatPromptBytes}) {
    if (value is! String ||
        !chatValidUnicode(value) ||
        utf8.encode(value).length > maxBytes) {
      throw const FormatException('Teks snapshot tidak valid');
    }
    return value;
  }

  static String _readable(String value) {
    try {
      return text(value);
    } on FormatException {
      return '';
    }
  }

  static int integer(Object? value, {int min = 0}) {
    if (value is! int || value < min) {
      throw const FormatException('Angka snapshot tidak valid');
    }
    return value;
  }

  static Map map(Object? value) {
    if (value is! Map) {
      throw const FormatException('Objek snapshot tidak valid');
    }
    return value;
  }

  static List list(Object? value) {
    if (value is! List) {
      throw const FormatException('Daftar snapshot tidak valid');
    }
    return value;
  }

  static Map<String, Object> anchorData(SourceAnchor a) => {
    'bookId': a.book.bookId,
    'contentRevision': a.book.contentRevision,
    'chapterId': a.chapterId,
    'paragraphIndex': a.paragraphIndex,
    'start': a.start,
    'end': a.end,
    'paragraphHash': a.paragraphHash,
    'snapshot': a.snapshot,
  };

  static SourceAnchor anchor(Object? value, ChatBookRef book) {
    final m = map(value);
    final ref = (
      bookId: integer(m['bookId'], min: 1),
      contentRevision: integer(m['contentRevision'], min: 1),
    );
    final start = integer(m['start']);
    final end = integer(m['end'], min: start + 1);
    final snapshot = text(m['snapshot']);
    final hash = text(m['paragraphHash']);
    if (ref != book ||
        snapshot.length != end - start ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('Anchor snapshot tidak cocok');
    }
    return SourceAnchor(
      book: ref,
      chapterId: integer(m['chapterId'], min: 1),
      paragraphIndex: integer(m['paragraphIndex']),
      start: start,
      end: end,
      paragraphHash: hash,
      snapshot: snapshot,
    );
  }

  static List<SourceAnchor> anchors(Object? value, ChatBookRef book) {
    final result = [for (final a in list(value)) anchor(a, book)];
    if (result.isEmpty) throw const FormatException('Anchor kosong');
    return result;
  }

  static List<Map<String, Object>> sourcesData(List<ChatSource> sources) => [
    for (final s in sources)
      {
        'id': s.id,
        'chapterTitle': s.chapterTitle,
        'anchors': [for (final a in s.anchors) anchorData(a)],
      },
  ];

  static List<ChatSource> sources(String raw, ChatBookRef book) {
    final rows = list(json(raw));
    if (rows.length > chatMaxSources) {
      throw const FormatException('Terlalu banyak sumber');
    }
    final ids = <String>{};
    final result = <ChatSource>[];
    for (final value in rows) {
      final m = map(value);
      final id = text(m['id']);
      if (!RegExp(r'^S[1-9]\d*$').hasMatch(id) || !ids.add(id)) {
        throw const FormatException('ID sumber rusak');
      }
      final range = anchors(m['anchors'], book);
      for (var i = 1; i < range.length; i++) {
        final a = range[i - 1], b = range[i];
        if (a.chapterId != b.chapterId ||
            a.paragraphIndex > b.paragraphIndex ||
            a.paragraphIndex == b.paragraphIndex && a.end > b.start) {
          throw const FormatException('Urutan sumber rusak');
        }
      }
      result.add(
        ChatSource(
          id: id,
          chapterTitle: text(m['chapterTitle']),
          anchors: range,
        ),
      );
    }
    return List.unmodifiable(result);
  }

  static Map<String, Object> quoteData(ChatQuote quote) => {
    'anchors': [for (final a in quote.anchors) anchorData(a)],
    if (quote.translation != null) 'translation': quote.translation!,
  };

  static ChatQuote? quote(String? raw, ChatBookRef book) {
    if (raw == null) return null;
    final m = map(json(raw));
    return ChatQuote(
      anchors: anchors(m['anchors'], book),
      translation: m['translation'] == null ? null : text(m['translation']),
    );
  }

  static Map<String, Object> answerData(ChatAnswer answer) => {
    if (answer.formatVersion == 2) 'formatVersion': 2,
    'status': answer.status.wireValue,
    (answer.formatVersion == 2 ? 'parts' : 'claims'): [
      for (final b in answer.blocks)
        {
          'text': b.text,
          if (answer.formatVersion == 2) 'kind': b.kind.name,
          'sourceIds': [for (final s in b.sources) s.id],
        },
    ],
  };

  static ChatAnswer? answer(String? raw, List<ChatSource> sources) {
    if (raw == null) return null;
    final m = map(decodeChatAnswerJson(raw));
    final version = m.containsKey('formatVersion')
        ? integer(m['formatVersion'], min: 1)
        : 1;
    if (version != 1 && version != 2) {
      throw const FormatException('Versi jawaban tidak dikenal');
    }
    final rows = list(m[version == 2 ? 'parts' : 'claims']);
    if (version == 1 && rows.length > 2) {
      throw const FormatException('Terlalu banyak klaim');
    }
    final byId = {for (final s in sources) s.id: s};
    final blocks = <ChatAnswerBlock>[];
    for (final value in rows) {
      final claim = map(value);
      final ids = list(claim['sourceIds']);
      if (version == 1 && ids.isEmpty ||
          ids.toSet().length != ids.length ||
          ids.any((id) => id is! String || !byId.containsKey(id))) {
        throw const FormatException('Referensi klaim tidak cocok');
      }
      blocks.add(
        ChatAnswerBlock(
          text: text(claim['text']),
          kind: version == 2
              ? ChatAnswerKind.parse(claim['kind'])
              : ChatAnswerKind.book,
          sources: [for (final id in ids) byId[id]!],
        ),
      );
    }
    return ChatAnswer(
      status: ChatAnswerStatus.parse(m['status']),
      blocks: blocks,
      formatVersion: version,
    );
  }

  static Map<String, Object> scrollData(ChatScrollAnchor anchor) => {
    'turnId': anchor.turnId,
    'blockIndex': anchor.blockIndex,
    'alignment': anchor.alignment,
  };

  static ChatScrollAnchor scroll(String raw) {
    final m = map(json(raw, maxBytes: 512));
    final alignment = m['alignment'];
    if (alignment is! num ||
        !alignment.isFinite ||
        alignment < 0 ||
        alignment > 1) {
      throw const FormatException('Alignment tidak valid');
    }
    return (
      turnId: integer(m['turnId'], min: 1),
      blockIndex: integer(m['blockIndex']),
      alignment: alignment.toDouble(),
    );
  }

  static ChatSession session(ChatSessionRow row, {String? preview}) {
    var title = 'Obrolan tidak valid';
    var invalid = false;
    ChatScrollAnchor? anchor;
    try {
      title = chatTitle(row.title);
      integer(row.contentRevision, min: 1);
      if (row.scrollAnchor != null) anchor = scroll(row.scrollAnchor!);
      if (preview != null) preview = chatQuestion(preview);
    } on FormatException {
      invalid = true;
      preview = null;
    }
    return ChatSession(
      id: row.id,
      book: (bookId: row.bookId, contentRevision: row.contentRevision),
      title: title,
      manualTitle: row.manualTitle,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      lastOpenedAt: row.lastOpenedAt,
      scrollAnchor: anchor,
      preview: preview,
      invalid: invalid,
    );
  }

  static ChatTurn turn(
    ChatTurnRow row,
    ChatSessionRow session, {
    bool strict = false,
  }) {
    final book = (
      bookId: session.bookId,
      contentRevision: session.contentRevision,
    );
    final phase = ChatPhase.restore(row.phase);
    try {
      integer(book.contentRevision, min: 1);
      integer(row.sequence);
      integer(row.attempt, min: 1);
      integer(row.promptVersion, min: 1);
      if (text(row.model).trim().isEmpty) {
        throw const FormatException('Model kosong');
      }
      final question = chatQuestion(row.question);
      final draft = text(row.draft);
      final evidence = sources(row.sources, book);
      final result = answer(row.answer, evidence);
      AiError? error;
      if (row.error != null) {
        error = AiError.values.where((e) => e.name == row.error).firstOrNull;
        if (error == null) throw const FormatException('Error tidak dikenal');
      }
      if (row.httpStatus != null &&
              (row.httpStatus! < 100 || row.httpStatus! > 599) ||
          phase == ChatPhase.done && (result == null || error != null) ||
          phase != ChatPhase.done && result != null ||
          phase == ChatPhase.failed && error == null ||
          phase.isRunning && error != null) {
        throw const FormatException('Status turn tidak konsisten');
      }
      return ChatTurn(
        id: row.id,
        sessionId: row.sessionId,
        book: book,
        sequence: row.sequence,
        question: question,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        phase: phase,
        model: row.model,
        promptVersion: row.promptVersion,
        attempt: row.attempt,
        quote: quote(row.quote, book),
        draft: draft,
        answer: result,
        error: error,
        httpStatus: row.httpStatus,
      );
    } on FormatException {
      if (strict) rethrow;
      return ChatTurn(
        id: row.id,
        sessionId: row.sessionId,
        book: book,
        sequence: row.sequence,
        question: _readable(row.question),
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        phase: phase == ChatPhase.interrupted ? phase : ChatPhase.failed,
        model: _readable(row.model),
        promptVersion: row.promptVersion,
        attempt: row.attempt,
        draft: _readable(row.draft),
        error: AiError.invalidResponse,
      );
    }
  }
}
