import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/chat_exploration.dart';
import 'package:luma/domain/chat_prompt.dart';
import 'package:luma/domain/chat_retrieval.dart';
import 'package:luma/domain/models/book_chat.dart';

void main() {
  const book = (bookId: 1, contentRevision: 2);
  final rows = <ChatIndexedParagraph>[
    for (var i = 0; i < 3; i++)
      (
        paragraph: (
          book: book,
          chapterId: i + 1,
          paragraphIndex: 0,
          text: '${'a' * 1199}😀${'long sentence ' * 200}',
        ),
        chapterTitle: 'Chapter $i',
        groupIndex: null,
      ),
  ];
  final windows = chatGlobalWindows(rows);
  final turn = ChatTurn(
    id: 1,
    sessionId: 5,
    book: book,
    sequence: 0,
    question: 'Whole book?',
    model: 'model',
    promptVersion: chatPromptVersion,
    phase: ChatPhase.stopped,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  ChatExploration work({
    int cursor = 2,
    List<ChatExplorationNote> notes = const [],
  }) => ChatExploration(
    book: book,
    sessionId: 5,
    turnId: 1,
    question: turn.question,
    model: 'model',
    manifest: chatWindowManifest(windows),
    query: 'Whole book?',
    cursor: cursor,
    total: windows.length,
    notes: notes,
  );

  test('global windows cover every original character once, including ungrouped text and surrogate boundaries', () {
    for (final row in rows) {
      final parts = windows.where(
        (w) => w.anchors.first.chapterId == row.paragraph.chapterId,
      );
      expect(parts.map((p) => p.text).join(), row.paragraph.text);
      var cursor = 0;
      for (final part in parts) {
        final a = part.anchors.single;
        expect(a.start, cursor);
        a.validate(row.paragraph, book);
        expect(chatValidUnicode(a.snapshot), isTrue);
        cursor = a.end;
      }
      expect(cursor, row.paragraph.text.length);
    }
    expect(
      windows.map((w) => w.anchors.first.chapterId),
      orderedEquals([1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3]),
    );
  });

  test('packing preserves every cited original range, merges overlaps and keeps chapter gaps', () {
    final packed = chatPackGlobalSources([
      ...windows,
      windows.first,
      windows.last,
    ]);
    expect(packed, hasLength(3));
    for (final (i, source) in packed.indexed) {
      expect(source.anchors, hasLength(1));
      expect(source.text, rows[i].paragraph.text);
      source.anchors.single.validate(rows[i].paragraph, book);
    }
    final gapped = chatPackGlobalSources([windows.first, windows[2]]).single;
    expect(gapped.anchors, hasLength(2));
    expect(gapped.anchors.first.end, lessThan(gapped.anchors.last.start));
  });

  test('checkpoint round trip validates identity, manifest and only examined sources', () {
    final value = work(
      notes: [
        (text: 'Opening idea', sourceIds: ['S1']),
      ],
    );
    final decoded = ChatExploration.parse(value.encode());
    decoded.validate(turn, windows);
    expect(decoded.cursor, 2);
    expect(decoded.complete, isFalse);
    expect(
      () => decoded.validate(turn, windows.reversed.toList()),
      throwsFormatException,
    );
    expect(
      () => work(
        notes: [
          (text: 'Not read', sourceIds: ['S3']),
        ],
      ).validate(turn, windows),
      throwsFormatException,
    );
    for (final entry in {
      'policy': 99,
      'cursor': -1,
      'total': 1,
      'question': 1,
      'notes': null,
    }.entries) {
      expect(
        () => ChatExploration.parse(
          jsonEncode({...value.data, entry.key: entry.value}),
        ),
        throwsFormatException,
      );
    }
  });

  test(
    'interruption preserves progress and explicit incompatible retry clears it',
    () {
      final previous = ChatTurn(
        id: 1,
        sessionId: 5,
        book: book,
        sequence: 0,
        question: 'Whole book?',
        model: 'model',
        promptVersion: chatPromptVersion,
        phase: ChatPhase.retrieving,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        exploration: work().encode(),
      );
      final stopped = previous.interrupt(DateTime(2026), cancelled: true);
      expect(stopped.exploration, previous.exploration);
      expect(
        stopped
            .retry(
              current: book,
              isLatest: true,
              at: DateTime(2026),
              model: 'model',
              promptVersion: chatPromptVersion,
            )
            .exploration,
        previous.exploration,
      );
      expect(
        stopped
            .retry(
              current: book,
              isLatest: true,
              at: DateTime(2026),
              model: 'other',
              promptVersion: chatPromptVersion,
            )
            .exploration,
        isNull,
      );
    },
  );

  test('note parser rejects invented IDs, duplicate keys, oversized text and empty citations', () {
    for (final raw in [
      '{"notes":[],"notes":[]}',
      jsonEncode({
        'notes': [
          {
            'text': 'Invented',
            'source_ids': ['S9'],
          },
        ],
      }),
      jsonEncode({
        'notes': [
          {
            'text': 'a' * 1201,
            'source_ids': ['S1'],
          },
        ],
      }),
      jsonEncode({
        'notes': [
          {'text': 'Fact', 'source_ids': []},
        ],
      }),
    ]) {
      expect(
        () => parseChatGlobalNotes(raw, allowed: {'S1'}),
        throwsFormatException,
      );
    }
  });

  test('planner strategies and follow-up query counts are bounded and old plans remain readable', () {
    for (final strategy in ChatSearchStrategy.values) {
      final plan = parseChatQueryPlan(
        jsonEncode({
          'query': 'book?',
          'needs_clarification': false,
          'strategy': strategy.name,
          'queries': ['first?', 'last?'],
        }),
      );
      expect(plan.strategy, strategy);
      expect(plan.queries, ['first?', 'last?']);
    }
    expect(
      parseChatQueryPlan('{"query":"book?","needs_clarification":false}')
          .strategy,
      ChatSearchStrategy.specific,
    );
    expect(
      () => parseChatQueryPlan(
        '{"query":"book?","needs_clarification":false,"strategy":"fake"}',
      ),
      throwsFormatException,
    );
    expect(
      () => chatMissingQueries('{"missing_queries":["a","b","c"]}'),
      throwsFormatException,
    );
  });
}
