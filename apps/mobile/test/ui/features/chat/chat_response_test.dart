import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/models/book_chat.dart';
import 'package:luma/ui/features/chat/views/chat_response.dart';

import 'chat_test.dart' as fixtures;

void main() {
  testWidgets(
    'paces graphemes, delays sources, drains final and reopens instantly',
    (t) async {
      List<ChatAnswerBlock> visible = [];
      final source = fixtures.source;
      final text = '👩🏽‍💻e\u0301 ' * 100;
      Future<void> show(ChatPhase phase, {Key? key, bool reduced = false}) =>
          t.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(disableAnimations: reduced),
                child: ChatResponse(
                  key: key,
                  phase: phase,
                  blocks: [
                    ChatAnswerBlock(text: text, sources: [source]),
                  ],
                  builder: (_, blocks) {
                    visible = blocks;
                    return Text(blocks.first.text);
                  },
                ),
              ),
            ),
          );
      await show(ChatPhase.writing);
      await t.pump(const Duration(milliseconds: 100));
      expect(visible.first.text, isNotEmpty);
      expect(visible.first.text.length, lessThan(text.length));
      expect(visible.first.sources, isEmpty);
      expect(
        text.characters
            .toList()
            .take(visible.first.text.characters.length)
            .join(),
        visible.first.text,
      );
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      await show(ChatPhase.done);
      await t.pump(const Duration(milliseconds: 300));
      expect(visible.first.text.length, lessThan(text.length));
      await t.pumpAndSettle();
      expect(visible.first.text, text);
      expect(visible.first.sources, [source]);
      await show(ChatPhase.done, key: const ValueKey('cache'));
      expect(visible.first.text, text);
      await show(
        ChatPhase.writing,
        key: const ValueKey('reduced'),
        reduced: true,
      );
      expect(visible.first.text, text);
    },
  );

  testWidgets('background flushes safe tail; a new attempt starts fresh', (
    t,
  ) async {
    List<ChatAnswerBlock> visible = [];
    Future<void> show(int attempt, ChatPhase phase, String text) =>
        t.pumpWidget(
          MaterialApp(
            home: ChatResponse(
              key: ValueKey(attempt),
              phase: phase,
              blocks: [ChatAnswerBlock(text: text, sources: [])],
              builder: (_, blocks) {
                visible = blocks;
                return Text(blocks.first.text);
              },
            ),
          ),
        );
    final text = 'Teks aman ' * 100;
    await show(1, ChatPhase.writing, text);
    await t.pump(const Duration(milliseconds: 100));
    expect(visible.first.text, isNot(text));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await t.pump();
    expect(visible.first.text, text);
    await show(1, ChatPhase.writing, '$text lagi');
    expect(visible.first.text, '$text lagi');
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await show(2, ChatPhase.writing, 'Retry baru');
    expect(visible.first.text, isEmpty);
    await show(2, ChatPhase.done, 'Retry baru');
    await t.pumpAndSettle();
    expect(visible.first.text, 'Retry baru');
    await t.pumpWidget(const SizedBox());
    expect(t.takeException(), isNull);
  });

  for (final terminal in [
    ChatPhase.stopped,
    ChatPhase.cut,
    ChatPhase.failed,
    ChatPhase.interrupted,
  ]) {
    testWidgets('$terminal reveals safe text and removes provisional sources', (
      t,
    ) async {
      List<ChatAnswerBlock> visible = [];
      Future<void> show(ChatPhase phase) => t.pumpWidget(
        MaterialApp(
          home: ChatResponse(
            phase: phase,
            blocks: [ChatAnswerBlock(text: 'Teks aman ' * 100, sources: [])],
            builder: (_, blocks) {
              visible = blocks;
              return Text(blocks.first.text);
            },
          ),
        ),
      );
      await show(ChatPhase.writing);
      await t.pump(const Duration(milliseconds: 100));
      expect(visible.first.text.length, lessThan(1000));
      await show(terminal);
      expect(visible.first.text, 'Teks aman ' * 100);
      expect(visible.first.sources, isEmpty);
      await t.pumpAndSettle();
    });
  }
}
