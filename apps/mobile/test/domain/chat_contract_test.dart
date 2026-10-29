import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/chat_prompt.dart';
import 'package:luma/domain/models/ai_reply.dart';
import 'package:luma/domain/models/book_chat.dart';

void main() {
  const book = (bookId: 1, contentRevision: 1);
  const changed = (bookId: 1, contentRevision: 2);
  const foreign = (bookId: 2, contentRevision: 1);
  final now = DateTime.utc(2026, 10, 28);
  const original = 'A😀BC original evidence.';
  const ChatParagraph paragraph = (
    book: book,
    chapterId: 7,
    paragraphIndex: 3,
    text: original,
  );
  final paragraphs = {(chapterId: 7, paragraphIndex: 3): paragraph};
  SourceAnchor anchor({
    ChatBookRef owner = book,
    int start = 0,
    int? end,
    String? hash,
    String? snapshot,
  }) => SourceAnchor(
    book: owner,
    chapterId: 7,
    paragraphIndex: 3,
    start: start,
    end: end ?? original.length,
    paragraphHash: hash ?? chatTextHash(original),
    snapshot: snapshot ?? original.substring(start, end),
  );
  ChatSource source({String id = 'S1', SourceAnchor? a}) =>
      ChatSource(id: id, chapterTitle: 'Chapter', anchors: [a ?? anchor()]);
  final s = source();
  ChatAnswer answer({
    ChatAnswerStatus status = ChatAnswerStatus.answered,
    String text = 'Supported.',
  }) => ChatAnswer(
    status: status,
    blocks: status == ChatAnswerStatus.notFound
        ? []
        : [
            ChatAnswerBlock(text: text, sources: [s]),
          ],
  );
  ChatSession session({int id = 10, ChatBookRef owner = book}) => ChatSession(
    id: id,
    book: owner,
    title: 'Question',
    manualTitle: false,
    createdAt: now,
    updatedAt: now,
  );
  ChatTurn turn({
    int id = 1,
    int sessionId = 10,
    ChatBookRef owner = book,
    int sequence = 1,
    ChatPhase phase = ChatPhase.done,
    ChatAnswer? reply,
    String question = 'Earlier question',
    AiError? error,
    String draft = '',
  }) => ChatTurn(
    id: id,
    sessionId: sessionId,
    book: owner,
    sequence: sequence,
    question: question,
    createdAt: now,
    updatedAt: now,
    phase: phase,
    model: 'test-model',
    promptVersion: chatPromptVersion,
    answer: reply ?? (phase == ChatPhase.done ? answer() : null),
    draft: draft,
    error: error,
  );
  ChatPrompt prompt({
    List<ChatSource>? sources,
    List<ChatTurn> history = const [],
    ChatQuote? quote,
    ChatBookRef current = book,
    String question = 'What happened?',
    String title = 'Book',
  }) => buildChatPrompt(
    session: session(),
    current: current,
    question: question,
    beforeSequence: 99,
    history: history,
    sources: sources ?? [s],
    paragraphs: paragraphs,
    title: title,
    quote: quote,
  );
  String raw(
    String status, {
    List<Object>? claims,
    String note = 'INVENTED FACT',
  }) => jsonEncode({
    'status': status,
    'claims':
        claims ??
        [
          {
            'text': 'Supported.',
            'source_ids': ['S1'],
          },
        ],
    'note': note,
  });
  ChatAnswer parse(String value, {List<ChatSource>? sources}) =>
      parseChatAnswer(
        value,
        sources: sources ?? [s],
        current: book,
        paragraphs: paragraphs,
      );

  test('anchors enforce book/revision/hash, range and UTF-16 boundaries', () {
    anchor().validate(paragraph, book);
    anchor(start: 1, end: 3, snapshot: '😀').validate(paragraph, book);
    for (final a in [
      anchor(owner: foreign),
      anchor(owner: changed),
      anchor(hash: 'stale'),
      anchor(snapshot: 'fabricated'),
      anchor(start: 2, end: 3, snapshot: original.substring(2, 3)),
      anchor(start: 1, end: 2, snapshot: original.substring(1, 2)),
      anchor(start: -1, snapshot: 'x'),
      anchor(end: 100, snapshot: 'x'),
    ]) {
      expect(() => a.validate(paragraph, book), throwsFormatException);
    }
    expect(() => anchor().validate(paragraph, changed), throwsFormatException);
    expect(
      () => anchor().validate((
        book: book,
        chapterId: 8,
        paragraphIndex: 3,
        text: original,
      ), book),
      throwsFormatException,
    );
  });

  test('natural replies preserve book references without forcing every paragraph into a claim', () {
    final result = parse(
      jsonEncode({
        'status': 'answered',
        'parts': [
          {
            'text': 'Dari buku.',
            'kind': 'book',
            'source_ids': ['S1'],
          },
          {
            'text': 'Kalau diterapkan, saran gua begini.',
            'kind': 'interpretation',
            'source_ids': ['S1'],
          },
          {
            'text': 'Sebagai pengetahuan tambahan.',
            'kind': 'external',
            'source_ids': [],
          },
          {
            'text': 'Ada bagian yang perlu lo perjelas?',
            'kind': 'conversation',
            'source_ids': [],
          },
        ],
      }),
    );
    expect(result.formatVersion, 2);
    expect(result.blocks, hasLength(4));
    expect(result.blocks.map((b) => b.kind), ChatAnswerKind.values);
    expect(identical(result.blocks.first.sources.single, s), isTrue);
    expect(result.note, isEmpty);
    expect(chatPromptVersion, 3);
  });

  test('partial, clarification and off-topic responses can explain themselves without book evidence', () {
    for (final status in ['partial', 'clarify', 'off_topic']) {
      final result = parse(
        jsonEncode({
          'status': status,
          'parts': [
            {
              'text': 'Penjelasan atau pertanyaan lanjutan.',
              'kind': 'conversation',
              'source_ids': [],
            },
          ],
        }),
        sources: [],
      );
      expect(result.note, isEmpty);
      expect(turn(reply: result).trustedHistory, isTrue);
    }
  });

  test('natural answers reject invented citations, false provenance and duplicate keys', () {
    for (final part in [
      {'text': 'X', 'kind': 'book', 'source_ids': []},
      {
        'text': 'X',
        'kind': 'book',
        'source_ids': ['S99'],
      },
      {
        'text': 'X',
        'kind': 'book',
        'source_ids': ['S1', 'S1'],
      },
      {
        'text': 'X',
        'kind': 'external',
        'source_ids': ['S1'],
      },
      {'text': 'X', 'kind': 'unknown', 'source_ids': []},
    ]) {
      expect(
        () => parse(
          jsonEncode({
            'status': 'answered',
            'parts': [part],
          }),
        ),
        throwsFormatException,
      );
    }
    expect(
      () => parse(
        r'{"status":"partial","parts":[],"pa\u0072ts":[{"text":"Lost caveat","kind":"conversation","source_ids":[]}]}',
      ),
      throwsFormatException,
    );
  });

  test(
    'explicit quote spans windows without cutting text or trusting translation',
    () {
      final quote = ChatQuote(
        anchors: [anchor(start: 1, end: 5, snapshot: original.substring(1, 5))],
        translation: 'NOT EVIDENCE',
      );
      final first = source(
        a: anchor(start: 0, end: 3, snapshot: original.substring(0, 3)),
      );
      final second = source(
        id: 'S2',
        a: anchor(
          start: 3,
          end: original.length,
          snapshot: original.substring(3),
        ),
      );
      final built = prompt(sources: [first, second], quote: quote);
      final data = jsonDecode(built.user) as Map;
      expect(data['selectedQuote'], '😀BC');
      expect(data['selectedSourceIds'], ['S1', 'S2']);
      expect(built.user.contains('NOT EVIDENCE'), isFalse);
      expect(
        () => prompt(sources: [first], quote: quote),
        throwsFormatException,
      );
      expect(
        () => prompt(
          quote: ChatQuote(anchors: [anchor(owner: foreign)]),
        ),
        throwsFormatException,
      );
      expect(
        () => prompt(
          sources: [
            second,
            source(id: 'S2'),
          ],
        ),
        throwsFormatException,
      );
      expect(
        () => prompt(
          sources: [
            ChatSource(
              id: 'S1',
              chapterTitle: 'X',
              anchors: [second.anchors.first, first.anchors.first],
            ),
          ],
        ),
        throwsFormatException,
      );
    },
  );

  test('history keeps completed conversation but excludes other sessions, nonfinal and later turns', () {
    final built = prompt(
      history: [
        turn(id: 1, sequence: 1),
        turn(id: 2, sequence: 2),
        turn(id: 3, sessionId: 11),
        turn(id: 4, owner: foreign),
        turn(id: 5, owner: changed),
        turn(id: 6, phase: ChatPhase.stopped, draft: 'UNTRUSTED'),
        turn(
          id: 7,
          sequence: 3,
          reply: answer(status: ChatAnswerStatus.partial),
        ),
        turn(id: 8, phase: ChatPhase.writing),
        turn(id: 9, error: AiError.invalidResponse),
        turn(id: 10, sequence: 100),
        turn(
          id: 11,
          sequence: 4,
          reply: answer(status: ChatAnswerStatus.notFound),
        ),
      ],
    );
    expect(built.historyTurnIds, [1, 2, 7, 11]);
    expect(built.user.contains('UNTRUSTED'), isFalse);
    final large = answer(text: 'x' * (chatHistoryBytes ~/ 2 + 1));
    final bounded = prompt(
      history: [
        turn(id: 1, sequence: 1, reply: large),
        turn(id: 2, sequence: 2, reply: large),
      ],
    );
    expect(bounded.historyTurnIds, [2]);
    final perClaimCopies = ChatAnswer(
      status: ChatAnswerStatus.answered,
      blocks: [
        ChatAnswerBlock(text: 'One', sources: [source()]),
        ChatAnswerBlock(text: 'Two', sources: [source()]),
      ],
    );
    expect(prompt(history: [turn(reply: perClaimCopies)]).historyTurnIds, [1]);
    expect(() => prompt(current: changed), throwsFormatException);
  });

  test(
    'JSON IDs are bound to sent snapshots; model notes never become facts',
    () {
      final supported = parse(raw('answered'));
      expect(identical(supported.blocks.first.sources.first, s), isTrue);
      expect(supported.note, isEmpty);
      for (final status in ['partial', 'not_found']) {
        final result = parse(
          raw(status, claims: status == 'not_found' ? [] : null),
        );
        expect(result.note.contains('INVENTED'), isFalse);
        expect(result.note, isNotEmpty);
      }
      for (final bad in [
        raw('unknown'),
        raw('answered', claims: []),
        raw('not_found'),
        raw(
          'answered',
          claims: [
            {
              'text': 'X',
              'source_ids': ['S99'],
            },
          ],
        ),
        raw(
          'answered',
          claims: [
            {
              'text': 'X',
              'source_ids': ['S1', 'S1'],
            },
          ],
        ),
        raw(
          'answered',
          claims: [
            {
              'text': ' ',
              'source_ids': ['S1'],
            },
          ],
        ),
        raw(
          'answered',
          claims: List.filled(3, {
            'text': 'X',
            'source_ids': ['S1'],
          }),
        ),
        '{"status":"answered","claims":[]}',
        'not JSON',
      ]) {
        expect(() => parse(bad), throwsFormatException);
      }
      expect(
        () => parse(
          raw('answered'),
          sources: [source(a: anchor(hash: 'stale'))],
        ),
        throwsFormatException,
      );
      expect(
        () => supported.blocks.add(supported.blocks.first),
        throwsUnsupportedError,
      );
      expect(
        () => supported.blocks.first.sources.clear(),
        throwsUnsupportedError,
      );
      expect(() => s.anchors.clear(), throwsUnsupportedError);
    },
  );

  test(
    'retry/restart keep one turn, discard late generations and never auto-send',
    () {
      final active = turn(phase: ChatPhase.writing, draft: 'Paid partial text');
      final restarted = active.interrupt(now.add(const Duration(seconds: 1)));
      expect(restarted.phase, ChatPhase.interrupted);
      expect(restarted.draft, active.draft);
      expect(restarted.trustedHistory, isFalse);
      expect(restarted.accepts(active.attemptRef, book), isFalse);
      expect(active.accepts(active.attemptRef, book), isTrue);
      expect(active.accepts(active.attemptRef, changed), isFalse);
      expect(active.interrupt(now, cancelled: true).phase, ChatPhase.stopped);
      final retried = restarted.retry(
        current: book,
        isLatest: true,
        at: now,
        model: 'new-model',
        promptVersion: 1,
      );
      expect(
        (
          retried.id,
          retried.sessionId,
          retried.sequence,
          retried.question,
          retried.createdAt,
        ),
        (
          active.id,
          active.sessionId,
          active.sequence,
          active.question,
          active.createdAt,
        ),
      );
      expect(retried.attempt, 2);
      expect(retried.draft, isEmpty);
      expect(retried.answer, isNull);
      expect(retried.accepts(active.attemptRef, book), isFalse);
      expect(retried.accepts(retried.attemptRef, book), isTrue);
      for (final phase in ChatPhase.values.where((p) => p.isRunning)) {
        expect(turn(phase: phase).interrupt(now).phase, ChatPhase.interrupted);
      }
      expect(ChatPhase.restore('CORRUPT'), ChatPhase.interrupted);
      expect(ChatPhase.restore(null), ChatPhase.interrupted);
      expect(ChatPhase.restore('done'), ChatPhase.done);
      expect(
        () => restarted.retry(
          current: changed,
          isLatest: true,
          at: now,
          model: 'm',
          promptVersion: 1,
        ),
        throwsStateError,
      );
      expect(
        () => restarted.retry(
          current: book,
          isLatest: false,
          at: now,
          model: 'm',
          promptVersion: 1,
        ),
        throwsStateError,
      );
      expect(
        () => turn().retry(
          current: book,
          isLatest: true,
          at: now,
          model: 'm',
          promptVersion: 1,
        ),
        throwsStateError,
      );
    },
  );

  test('Unicode input and all budgets fail explicitly rather than truncating evidence', () {
    expect(chatQuestion('  😀 pertanyaan  '), '😀 pertanyaan');
    expect(chatQuestion('😀' * 500).length, 1000);
    for (final bad in ['', '   ', '😀' * 501, String.fromCharCode(0xd800)]) {
      expect(() => chatQuestion(bad), throwsFormatException);
    }
    expect(chatTitle('  Judul\n buku  '), 'Judul buku');
    expect(chatTitle('😀' * 121, automatic: true).runes.length, 120);
    expect(() => chatTitle('😀' * 121), throwsFormatException);
    expect(() => chatTitle('  '), throwsFormatException);
    expect(() => prompt(title: 'x' * chatPromptBytes), throwsFormatException);
    expect(
      () => prompt(
        sources: List.generate(
          chatMaxSources + 1,
          (i) => source(id: 'S${i + 1}'),
        ),
      ),
      throwsFormatException,
    );
    final huge = ChatSource(
      id: 'S1',
      chapterTitle: 'x' * chatSourceBytes,
      anchors: [anchor()],
    );
    expect(fitChatSources([huge, s]), [s]);
    expect(() => prompt(sources: [huge]), throwsFormatException);
    expect(
      fitChatSources(
        List.generate(chatMaxSources + 2, (i) => source(id: 'S${i + 1}')),
      ).length,
      chatMaxSources,
    );
  });

  test('entry and source visits preserve reader return position and session ownership', () {
    const position = (chapterId: 7, paragraphIndex: 3, paragraphOffset: 0.5);
    expect(
      ChatLaunchContext(book: book, returnPosition: position).startsNewSession,
      isFalse,
    );
    for (final origin in [
      ChatLaunchOrigin.meaning,
      ChatLaunchOrigin.breakdown,
    ]) {
      final entry = ChatLaunchContext(
        book: book,
        returnPosition: position,
        origin: origin,
        quote: ChatQuote(anchors: [anchor()]),
      );
      expect(entry.startsNewSession, isTrue);
      expect(entry.returnPosition, position);
      expect(
        () => ChatLaunchContext(
          book: book,
          returnPosition: position,
          origin: origin,
        ),
        throwsFormatException,
      );
    }
    final visit = SourceVisitRequest(
      sessionId: 10,
      turnId: 1,
      anchor: anchor(),
      returnPosition: position,
      chatPosition: (turnId: 1, blockIndex: 0, alignment: 0.3),
    );
    visit.validate(
      session: session(),
      turn: turn(),
      paragraph: paragraph,
      current: book,
    );
    expect(
      () => visit.validate(
        session: session(id: 11),
        turn: turn(),
        paragraph: paragraph,
        current: book,
      ),
      throwsFormatException,
    );
    expect(
      () => visit.validate(
        session: session(),
        turn: turn(),
        paragraph: paragraph,
        current: changed,
      ),
      throwsFormatException,
    );
  });

  test('embedding index identity includes every compatibility boundary and query plans are typed', () {
    const key = (
      book: book,
      parserVersion: 1,
      chunkPolicyVersion: 1,
      embedding: ChatEmbeddingModel.qwen8b,
      queryTemplateVersion: 1,
    );
    expect(key.embedding.dimensions, 4096);
    expect(ChatEmbeddingModel.openaiLarge.dimensions, 3072);
    expect(
      key ==
          (
            book: book,
            parserVersion: 1,
            chunkPolicyVersion: 1,
            embedding: ChatEmbeddingModel.openaiLarge,
            queryTemplateVersion: 1,
          ),
      isFalse,
    );
    expect(
      key ==
          (
            book: changed,
            parserVersion: 1,
            chunkPolicyVersion: 1,
            embedding: ChatEmbeddingModel.qwen8b,
            queryTemplateVersion: 1,
          ),
      isFalse,
    );
    final plan = parseChatQueryPlan(
      '{"query":"Why did they take it?","needs_clarification":true}',
    );
    expect(plan.needsClarification, isTrue);
    for (final bad in [
      '{}',
      '{"query":"why?","needs_clarification":"true"}',
      '{"query":" ","needs_clarification":false}',
    ]) {
      expect(() => parseChatQueryPlan(bad), throwsFormatException);
    }
  });
}
