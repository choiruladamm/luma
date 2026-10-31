import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/domain/models/book_chat.dart';
import 'package:luma/domain/models/reader_prefs.dart';
import 'package:luma/ui/core/theme/reader_typography.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/core/theme/stabilo_tokens.dart';
import 'package:luma/ui/core/widgets/buttons.dart';
import 'package:luma/ui/features/bookshelf/view_models/bookshelf_view_model.dart';
import 'package:luma/ui/features/chat/view_models/chat_view_model.dart';
import 'package:luma/ui/features/chat/views/chat_composer.dart';
import 'package:luma/ui/features/chat/views/chat_context_card.dart';
import 'package:luma/ui/features/chat/views/chat_view.dart';

import 'chat_test.dart' show FakeChat, book, session, turn, source, button;

void main() {
  setUpAll(() async {
    for (final (family, file) in [
      ('Bricolage Grotesque', 'BricolageGrotesque-400.ttf'),
      ('Atkinson Hyperlegible', 'AtkinsonHyperlegible-400.ttf'),
    ]) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$file'))).load();
    }
  });

  late FakeChat vm;
  Future<void> open(
    WidgetTester t,
    ChatState state, {
    Brightness brightness = Brightness.light,
    bool reduced = true,
    ReaderPrefs? prefs,
  }) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    t.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(t.view.reset);
    vm = FakeChat(1, state);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          chatViewModelProvider(1).overrideWith(() => vm),
          booksStreamProvider.overrideWith((ref) => Stream.value([])),
          if (prefs != null)
            readerPrefsProvider.overrideWith((ref) => Stream.value(prefs)),
        ],
        child: RepaintBoundary(
          key: const ValueKey('capture'),
          child: MaterialApp(
            theme: stabiloTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: child!,
            ),
            home: const ChatView(bookId: 1),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'reading layout uses overlay chrome and one contextual retry $brightness',
      (t) async {
        final answer = ChatAnswer(
          formatVersion: 2,
          status: ChatAnswerStatus.answered,
          blocks: [
            ChatAnswerBlock(
              text: 'Marcus ngingetin dirinya buat memegang cara berpikir dan bersikap. Yang di luar kendali bukan tanggung jawab kita.\n\nBukan cuma nahan kesal: kita juga perlu memahami kenapa orang lain bersikap begitu.',
              sources: [source],
            ),
          ],
        );
        await open(
          t,
          ChatState(
            book: book,
            activeSession: session(1),
            loading: false,
            turns: [
              turn(1, answer: answer),
              turn(2, phase: ChatPhase.stopped),
            ],
            phase: ChatPhase.stopped,
          ),
          brightness: brightness,
        );
        expect(find.text('Coba lagi'), findsOneWidget);
        final retry = find.widgetWithText(AppButton, 'Coba lagi');
        expect(t.getSize(retry).height, 36);
        await t.tapAt(
          t.getTopLeft(retry) + Offset(t.getSize(retry).width / 2, -3),
        );
        await t.pump();
        expect(vm.sends, 1);
        expect(find.byType(ChatComposer), findsOneWidget);
        final scroll = find.byType(CustomScrollView);
        expect(t.getRect(scroll), const Rect.fromLTWH(0, 0, 390, 844));
        expect(t.getRect(find.byType(ChatComposer)).bottom, 844 - 34 - 8);
        expect(
          t.getSize(find.byType(ChatComposer)).height,
          Layout.chatComposer,
        );
        final position = t
            .state<ScrollableState>(
              find
                  .descendant(of: scroll, matching: find.byType(Scrollable))
                  .first,
            )
            .position;
        position.jumpTo(position.minScrollExtent);
        await t.pumpAndSettle();
        expect(find.byType(ChatNotice), findsOneWidget);
        final originalTop = t.getTopLeft(button('Balik baca')).dy;
        // Header selalu ada: pas di-scroll cuma nama buku yang ngeringkas.
        expect(find.text('Ngobrolin buku'), findsOneWidget);
        expect(find.text('Buku ini'), findsOneWidget);
        await t.drag(scroll, const Offset(0, -200));
        await t.pumpAndSettle();
        expect(find.text('Ngobrolin buku'), findsOneWidget);
        expect(find.text('Buku ini'), findsNothing);
        expect(t.getTopLeft(button('Balik baca')).dy, originalTop);
        expect(t.getTopLeft(button('Riwayat obrolan')).dy, originalTop);
        await t.drag(scroll, const Offset(0, 400));
        await t.pumpAndSettle();
        expect(find.text('Buku ini'), findsOneWidget);
        expect(t.getTopLeft(button('Balik baca')).dy, originalTop);
        expect(t.takeException(), isNull);
        if (const bool.fromEnvironment('LUMA_DESIGN_CAPTURE')) {
          position.jumpTo(position.minScrollExtent);
          await t.pumpAndSettle();
          final boundary = t.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('capture')),
          );
          await t.runAsync(() async {
            final picture = await boundary.toImage();
            final bytes = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('/tmp/luma-redesign-${brightness.name}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            picture.dispose();
          });
        }
      },
    );
  }

  testWidgets(
    'normal motion aligns a new question once and streaming never follows',
    (t) async {
      final answer = ChatAnswer(
        formatVersion: 2,
        status: ChatAnswerStatus.answered,
        blocks: [
          ChatAnswerBlock(
            text: 'Gagasan panjang di buku. ' * 20,
            sources: [source],
          ),
        ],
      );
      await open(
        t,
        ChatState(
          book: book,
          loading: false,
          activeSession: session(1),
          turns: [for (var i = 1; i <= 5; i++) turn(i, answer: answer)],
        ),
        reduced: false,
      );
      final scroll = t
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      scroll.jumpTo(scroll.offset - 200);
      await t.pumpAndSettle();
      final latest = turn(6, phase: ChatPhase.writing);
      vm.push(
        vm.current.copyWith(
          turns: [...vm.current.turns, latest],
          phase: ChatPhase.writing,
        ),
      );
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(
        t.getTopLeft(find.text('Pertanyaan 6')).dy,
        inInclusiveRange(110, 140),
      );
      final offset = scroll.offset;
      vm.push(
        vm.current.copyWith(
          preview: (
            attempt: latest.attemptRef,
            blocks: [
              ChatAnswerBlock(
                text: 'Jawaban yang terus bertambah. ' * 200,
                sources: [],
              ),
            ],
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(scroll.offset, closeTo(offset, .01));
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'context expands once, collapses after send and never auto-sends',
    (t) async {
      final quote = ChatQuote(
        anchors: source.anchors,
        chapterTitle: 'Buku II',
        translation: 'Terjemahan lengkap untuk dibaca.',
      );
      await open(
        t,
        ChatState(book: book, loading: false, selectedQuote: quote),
      );
      expect(find.byType(ChatContextCard), findsOneWidget);
      expect(find.text(quote.translation!), findsNothing);
      expect(vm.sends, 0);
      await t.tap(find.byTooltip('Perluas konteks'));
      await t.pumpAndSettle();
      expect(find.text(quote.translation!), findsOneWidget);
      expect(vm.sends, 0);
      await t.enterText(find.byType(TextField), 'Apa maksudnya?');
      await t.pump();
      await t.tap(button('Kirim pertanyaan'));
      await t.pumpAndSettle();
      expect(vm.sends, 1);
      vm.push(
        vm.current.copyWith(
          turns: [turn(1, phase: ChatPhase.waiting)],
          phase: ChatPhase.waiting,
        ),
      );
      await t.pumpAndSettle();
      expect(find.text(quote.translation!), findsNothing);
      expect(find.byType(ChatContextCard), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  const aaPrefs = ReaderPrefs(
    font: ReadingFont.book,
    sizeStep: 6,
    spacing: LineSpacing.loose,
  );

  testWidgets('answer text and paragraph gap follow the Aa prefs', (t) async {
    final typo = ReaderTypography(aaPrefs, Brightness.light);
    final answer = ChatAnswer(
      formatVersion: 2,
      status: ChatAnswerStatus.answered,
      blocks: [
        ChatAnswerBlock(text: 'Paragraf satu.', sources: [source]),
        ChatAnswerBlock(text: 'Paragraf dua.', sources: [source]),
      ],
    );
    await open(
      t,
      ChatState(
        book: book,
        activeSession: session(1),
        loading: false,
        turns: [turn(1, answer: answer)],
      ),
      prefs: aaPrefs,
    );
    final first = find.byType(SelectableText).at(0);
    final second = find.byType(SelectableText).at(1);
    expect(t.widget<SelectableText>(first).style, typo.style);
    expect(
      t.widget<SelectableText>(first).style!.fontFamily,
      readingFamily(ReadingFont.book),
    );
    expect(t.widget<SelectableText>(first).style!.height, aaPrefs.lineHeight);
    final gap = t.getTopLeft(second).dy - t.getBottomLeft(first).dy;
    expect(gap, closeTo(typo.paragraphGap, 0.5));
  });

  testWidgets('context card text follows the Aa prefs', (t) async {
    final typo = ReaderTypography(aaPrefs, Brightness.light);
    final quote = ChatQuote(
      anchors: source.anchors,
      chapterTitle: 'Buku II',
      translation: 'Terjemahan lengkap untuk dibaca.',
    );
    await open(
      t,
      ChatState(book: book, loading: false, selectedQuote: quote),
      prefs: aaPrefs,
    );
    await t.tap(find.byTooltip('Perluas konteks'));
    await t.pumpAndSettle();
    final translation = t.widget<SelectableText>(
      find.widgetWithText(SelectableText, quote.translation!),
    );
    expect(translation.style, typo.style);
  });

  for (final margin in TextMargin.values) {
    testWidgets('text margin matches the reader for $margin', (t) async {
      final prefs = ReaderPrefs(margin: margin);
      final answer = ChatAnswer(
        formatVersion: 2,
        status: ChatAnswerStatus.answered,
        blocks: [
          ChatAnswerBlock(text: 'Satu paragraf.', sources: [source]),
        ],
      );
      await open(
        t,
        ChatState(
          book: book,
          activeSession: session(1),
          loading: false,
          turns: [turn(1, answer: answer)],
        ),
        prefs: prefs,
      );
      final reply = find.byType(SelectableText).first;
      expect(t.getTopLeft(reply).dx, prefs.marginWidth);
      expect(t.getSize(reply).width, 390 - 2 * prefs.marginWidth);
    });
  }
}
