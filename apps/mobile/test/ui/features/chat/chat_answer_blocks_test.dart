import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/models/book_chat.dart';
import 'package:luma/domain/models/reader_prefs.dart';
import 'package:luma/ui/core/theme/reader_typography.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/core/widgets/buttons.dart';
import 'package:luma/ui/features/chat/views/chat_answer_blocks.dart';
import 'package:luma/ui/features/chat/views/chat_response.dart';

import 'chat_test.dart' show source;

ChatAnswerBlock block(
  String text, {
  ChatAnswerLayout layout = ChatAnswerLayout.paragraph,
  ChatAnswerKind kind = ChatAnswerKind.book,
  bool cited = false,
}) => ChatAnswerBlock(
  text: text,
  layout: layout,
  kind: kind,
  sources: cited ? [source] : [],
);

void main() {
  const prefs = ReaderPrefs();
  final typo = ReaderTypography(prefs, Brightness.light);

  Future<void> pump(
    WidgetTester t,
    List<ChatAnswerBlock> blocks, {
    bool running = false,
  }) async {
    t.view.physicalSize = const Size(390, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: stabiloTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ChatAnswerBlocks(
              blocks: blocks,
              typo: typo,
              running: running,
              anchor: (_, child) => child,
              chip: (_) =>
                  const SizedBox(key: ValueKey('chip'), width: 20, height: 20),
            ),
          ),
        ),
      ),
    );
  }

  List<TextSpan> spans(WidgetTester t, Finder f) =>
      (t.widget<SelectableText>(f).textSpan!).children!
          .whereType<TextSpan>()
          .toList();

  testWidgets('bold and italic render as styles, never as asterisks', (
    t,
  ) async {
    await pump(t, [block('Ini **penting** dan *miring* ya.')]);
    expect(find.textContaining('*', findRichText: true), findsNothing);
    final s = spans(t, find.byType(SelectableText));
    expect(s.map((e) => e.text), [
      'Ini ',
      'penting',
      ' dan ',
      'miring',
      ' ya.',
    ]);
    expect(s[1].style!.fontWeight, FontWeight.w700);
    expect(s[3].style!.fontStyle, FontStyle.italic);
  });

  testWidgets('items are numbered by the app and sit closer than paragraphs', (
    t,
  ) async {
    await pump(t, [
      block('Intro.'),
      block('**Satu.** a', layout: ChatAnswerLayout.item),
      block('**Dua.** b', layout: ChatAnswerLayout.item),
      block('**Tiga.** c', layout: ChatAnswerLayout.item),
      block('Penutup.'),
      block('**Lagi.** d', layout: ChatAnswerLayout.item),
      block('**Juga.** e', layout: ChatAnswerLayout.item),
    ]);
    expect(find.text('1'), findsNWidgets(2));
    expect(find.text('2'), findsNWidgets(2));
    expect(find.text('3'), findsOneWidget);
    final all = find.byType(SelectableText);
    double gap(int a, int b) =>
        t.getTopLeft(all.at(b)).dy - t.getBottomLeft(all.at(a)).dy;
    expect(gap(1, 2), lessThan(gap(0, 1)));
    expect(gap(4, 5), closeTo(typo.paragraphGap, 1));
  });

  testWidgets('bullets have no numbers', (t) async {
    await pump(t, [
      block('a', layout: ChatAnswerLayout.bullet),
      block('b', layout: ChatAnswerLayout.bullet),
    ]);
    expect(find.text('1'), findsNothing);
    expect(find.byType(SelectableText), findsNWidgets(2));
  });

  testWidgets('quote sits in a muted block with the accent bar', (t) async {
    await pump(t, [block('Kutipan buku.', layout: ChatAnswerLayout.quote)]);
    expect(find.byType(ClipRRect), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ClipRRect),
        matching: find.byType(SelectableText),
      ),
      findsOneWidget,
    );
  });

  testWidgets('interpretation and external get one label per run', (t) async {
    await pump(t, [
      block('Dari buku.'),
      block('Tafsir satu.', kind: ChatAnswerKind.interpretation),
      block('Tafsir dua.', kind: ChatAnswerKind.interpretation),
      block('Info luar.', kind: ChatAnswerKind.external),
    ]);
    expect(find.text('TAFSIRAN'), findsOneWidget);
    expect(find.text('DI LUAR BUKU'), findsOneWidget);
  });

  testWidgets('conversation becomes a note card with an icon', (t) async {
    await pump(t, [
      block('Bukti belum ketemu.', kind: ChatAnswerKind.conversation),
    ]);
    expect(find.byType(AppIcon), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('caret only on the last block and only while running', (t) async {
    await pump(t, [block('Satu.'), block('Dua.')], running: true);
    expect(find.byType(ChatCaret), findsOneWidget);
    await pump(t, [block('Satu.'), block('Dua.')]);
    expect(find.byType(ChatCaret), findsNothing);
  });

  testWidgets('citation chips render after the text of their block', (t) async {
    await pump(t, [block('Ada sumbernya.', cited: true)]);
    expect(find.byKey(const ValueKey('chip')), findsOneWidget);
  });

  testWidgets('a colon intro labelled as a point renders as a paragraph', (
    t,
  ) async {
    await pump(t, [
      block(
        'Buat nerapin konsep ini, berikut beberapa contoh:',
        layout: ChatAnswerLayout.item,
      ),
      block('**Satu.** a', layout: ChatAnswerLayout.item),
      block('**Dua.** b', layout: ChatAnswerLayout.item),
    ]);
    // Nomor mulai dari butir pertama yang beneran daftar.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsNothing);
  });
}
