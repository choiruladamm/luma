import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/reading_progress_repository.dart';
import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/domain/models/reader_prefs.dart';
import 'package:luma/domain/models/ai_reply.dart';
import 'package:luma/domain/models/book.dart';
import 'package:luma/main.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/core/widgets/book_card.dart';
import 'package:luma/ui/core/widgets/buttons.dart';
import 'package:luma/ui/core/widgets/edge_fade.dart';
import 'package:luma/ui/core/widgets/switch.dart';
import 'package:luma/ui/features/bookshelf/view_models/bookshelf_view_model.dart';
import 'package:luma/ui/features/bookshelf/views/bookshelf_view.dart';
import 'package:luma/ui/core/widgets/tag.dart';
import 'package:luma/ui/features/reader/view_models/reader_view_model.dart';
import 'package:luma/ui/features/reader/views/reader_capsule.dart';
import 'package:luma/ui/features/reader/views/reader_view.dart';

import '../../../fakes.dart';

const book = ReaderBook(
  id: 1,
  title: 'The Enchiridion',
  totalChars: 300,
  chapters: [
    ChapterInfo(id: 10, title: 'I', charOffset: 0, chars: 100),
    ChapterInfo(id: 11, title: 'II', charOffset: 100, chars: 200),
  ],
);

const tallBook = ReaderBook(
  id: 1,
  title: 'The Enchiridion',
  totalChars: 3000,
  chapters: [
    ChapterInfo(id: 10, title: 'I', charOffset: 0, chars: 100),
    ChapterInfo(id: 13, title: 'Tall', charOffset: 100, chars: 2900),
  ],
);

ReaderParagraph p(int i, ParagraphType type, String text, [int? group]) =>
    ReaderParagraph(index: i, groupIndex: group, type: type, text: text);

/// A long chapter to scroll through: paragraph i reads "Line i ...".
final long = [
  for (var i = 0; i < 60; i++)
    p(i, ParagraphType.paragraph, 'Line $i of a long chapter.', i),
];

/// Multi-line paragraphs, so an offset inside one means something.
final tall = [
  for (var i = 0; i < 30; i++)
    p(i, ParagraphType.paragraph, 'Tall $i: ${'word ' * 30}'.trim(), i),
];

/// Groups already translated, per chapter (margin marks).
var translated = <int, Set<int>>{};

/// What the AI says for a group; tests swap it.
late Future<AiReply> Function(GroupRef) answer;

AiReply replyFor(GroupRef g) => AiReply(
  translations: [
    for (final p in paragraphs[g.chapterId]!)
      if (p.groupIndex == g.groupIndex) 'ID ${p.text}',
  ],
  meaning: 'Makna grup ${g.groupIndex}.',
);

final paragraphs = {
  12: long,
  13: tall,
  // One paragraph taller than the space above the sheet.
  14: [p(0, ParagraphType.paragraph, 'Huge: ${'word ' * 400}'.trim(), 0)],
  10: [
    p(0, ParagraphType.heading, 'I'), // same as the chapter title: hidden
    p(
      1,
      ParagraphType.paragraph,
      'There are things which are within our power.',
      0,
    ),
    p(2, ParagraphType.sceneBreak, '***'),
    p(
      3,
      ParagraphType.paragraph,
      'Conduct me, Zeus,\nWherever your decrees',
      1,
    ),
  ],
  11: [
    p(
      0,
      ParagraphType.paragraph,
      'Never say of anything, "I have lost it."',
      0,
    ),
  ],
};

void main() {
  late FakeProgress progress;

  setUp(() {
    translated = {};
    answer = (g) async => replyFor(g);
  });
  late FakeSettings settings;

  // Feeds the reader through its providers; no Drift in widget tests.
  Future<void> openBook(
    WidgetTester tester, {
    Brightness b = Brightness.light,
    ReaderBook readerBook = book,
    ReadingPosition? saved,
    ReaderPrefs prefs = const ReaderPrefs(),
  }) async {
    progress = FakeProgress(saved);
    settings = FakeSettings(prefs);
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = b;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groupAiProvider.overrideWith((ref, g) => answer(g)),
          settingsRepositoryProvider.overrideWithValue(settings),
          booksStreamProvider.overrideWith(
            (ref) => Stream.value([
              ShelfBook(
                id: 1,
                title: book.title,
                author: 'Epictetus',
                coverName: null,
                opened: true,
                createdAt: DateTime(2026, 10, 1),
              ),
            ]),
          ),
          readerBookProvider.overrideWith((ref, id) async => readerBook),
          readingProgressRepositoryProvider.overrideWithValue(progress),
          chapterParagraphsProvider.overrideWith(
            (ref, chapterId) async => paragraphs[chapterId]!,
          ),
          translatedGroupsProvider.overrideWith(
            (ref, id) => Stream.value(translated[id] ?? const {}),
          ),
          chapterTranslatedProvider.overrideWith(
            (ref, chapterId) async => chapterId == 10 ? 3 : 0,
          ),
          bookEndProvider.overrideWith(
            (ref, id) async => BookEnd(
              author: 'Epictetus',
              coverName: null,
              readingSeconds: 6 * 3600 + 20 * 60,
              translated: 86,
            ),
          ),
        ],
        child: const LumaApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BookCard));
    await tester.pumpAndSettle();
  }

  /// System back: works whether the capsule is showing or not.
  Future<void> leave(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  for (final b in Brightness.values) {
    testWidgets(
      'reads a chapter: heading, text, scene break, poem lines ($b)',
      (tester) async {
        await openBook(tester, b: b);
        expect(find.byType(ReaderView), findsOneWidget);
        expect(find.text('The Enchiridion'), findsOneWidget); // top bar
        expect(find.text('Bab 1'), findsOneWidget);
        expect(find.text('I'), findsOneWidget); // title shown once, not twice
        expect(
          find.text('There are things which are within our power.'),
          findsOneWidget,
        );
        expect(find.text('* * *'), findsOneWidget);
        expect(
          find.text('Conduct me, Zeus,\nWherever your decrees'),
          findsOneWidget,
        );
        expect(find.textContaining('%'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('chapter end card moves on to the next chapter', (tester) async {
    await openBook(tester);
    expect(find.text('Bab 1 kelar'), findsOneWidget);
    expect(find.text('3 paragraf diterjemahin'), findsOneWidget);
    expect(find.text('Lanjut ke II?'), findsOneWidget);
    expect(find.text('Bab 2 dari 2 · ±1 menit'), findsOneWidget);

    await tester.tap(find.text('Lanjut, gas'));
    await tester.pumpAndSettle();
    expect(find.text('Bab 2'), findsOneWidget);
    expect(
      find.text('Never say of anything, "I have lost it."'),
      findsOneWidget,
    );
    // Nothing translated here yet: no count.
    expect(find.textContaining('diterjemahin'), findsNothing);
    expect(find.text('Itu tadi bab terakhir!'), findsOneWidget);
  });

  for (final b in Brightness.values) {
    testWidgets('the last chapter leads to the book end screen ($b)', (
      tester,
    ) async {
      await openBook(tester, b: b);
      await tester.tap(find.text('Lanjut, gas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lanjut, gas'));
      await tester.pumpAndSettle();

      expect(find.text('kelar!'), findsOneWidget);
      expect(
        find.text(
          'The Enchiridion udah lo libas sampe kalimat terakhir. Keren sih.',
        ),
        findsOneWidget,
      );
      expect(find.text('6 jam 20 mnt'), findsOneWidget);
      expect(
        tester
            .widget<ReaderProgressLine>(find.byType(ReaderProgressLine))
            .progress,
        1,
      );
      expect(find.text('86'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('book end: read again from the start, or back to the shelf', (
    tester,
  ) async {
    await openBook(tester);
    await tester.tap(find.text('Lanjut, gas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut, gas'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Baca ulang dari awal'));
    await tester.pumpAndSettle();
    expect(find.text('Bab 1'), findsOneWidget);
    expect(progress.saves.last, (
      chapterId: 10,
      paragraphIndex: 0,
      paragraphOffset: 0.0,
    ));

    await tester.tap(find.text('Lanjut, gas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut, gas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Balik ke rak, cari buku lain'));
    await tester.pumpAndSettle();
    expect(find.byType(BookshelfView), findsOneWidget);

    await tester.tap(find.byType(BookCard));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut, gas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut, gas'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Tutup'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderView), findsNothing);
  });

  testWidgets('back button and "Udahan dulu" return to the shelf', (
    tester,
  ) async {
    await openBook(tester);
    await tester.tap(find.text('Udahan dulu, balik ke rak'));
    await tester.pumpAndSettle();
    expect(find.byType(BookshelfView), findsOneWidget);
    expect(find.byType(ReaderView), findsNothing);

    await tester.tap(find.byType(BookCard));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Balik ke rak'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderView), findsNothing);
  });

  group('Aa', () {
    final aaButton = find.byWidgetPredicate(
      (w) => w is CircleButton && w.semanticLabel == 'Atur tampilan teks',
    );

    Future<void> openAa(WidgetTester tester) async {
      await tester.tap(aaButton);
      await tester.pumpAndSettle();
    }

    TextStyle styleOf(WidgetTester tester, String text) =>
        tester.widget<Text>(find.textContaining(text)).style!;

    testWidgets('capsule stays above, Aa turns yellow, tap again closes', (
      tester,
    ) async {
      await openBook(tester);
      final center = tester.getCenter(aaButton);
      await openAa(tester);
      expect(find.text('Atur bacaan lo'), findsOneWidget);
      expect(tester.widget<CircleButton>(aaButton).active, isTrue);
      final capsule = tester.getRect(find.byType(ReaderTopCapsule));
      expect(
        tester.getRect(find.byType(BottomSheet)).top,
        greaterThan(capsule.bottom),
      );
      // The text behind stays visible for a live preview: light scrim.
      await tester.tapAt(center);
      await tester.pumpAndSettle();
      expect(find.text('Atur bacaan lo'), findsNothing);
      expect(tester.widget<CircleButton>(aaButton).active, isFalse);
    });

    testWidgets('size steps apply live and are saved', (tester) async {
      await openBook(tester);
      final para = 'There are things which are within our power.';
      expect(styleOf(tester, para).fontSize, 18.5);
      await openAa(tester);
      expect(find.text('18,5'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Gedein huruf'));
      await tester.pumpAndSettle();
      expect(find.text('20'), findsOneWidget);
      expect(styleOf(tester, para).fontSize, 20);
      expect(settings.prefs.sizeStep, 4);

      for (var i = 0; i < 6; i++) {
        await tester.tap(find.bySemanticsLabel('Kecilin huruf'));
        await tester.pumpAndSettle();
      }
      expect(settings.prefs.fontSize, 16); // stops at the smallest
    });

    testWidgets('font, line spacing and margin apply to the text', (
      tester,
    ) async {
      await openBook(tester);
      final para = 'There are things which are within our power.';
      await openAa(tester);
      await tester.tap(find.bySemanticsLabel('Font Kayak buku'));
      await tester.pumpAndSettle();
      expect(styleOf(tester, para).fontFamily, 'Literata');

      await tester.tap(find.text('Lega').first); // Jarak baris
      await tester.pumpAndSettle();
      expect(styleOf(tester, para).height, closeTo(1.9, 1e-9));

      await tester.tap(find.text('Sempit')); // Margin
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text(para)).dx, 16);
    });

    testWidgets('theme follows the choice', (tester) async {
      await openBook(tester);
      MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app().themeMode, ThemeMode.system);
      await openAa(tester);
      await tester.tap(find.bySemanticsLabel('Tema Gelap'));
      await tester.pumpAndSettle();
      expect(app().themeMode, ThemeMode.dark);
      await tester.tap(find.bySemanticsLabel('Tema Terang'));
      await tester.pumpAndSettle();
      expect(app().themeMode, ThemeMode.light);
    });

    testWidgets('progress line toggle', (tester) async {
      await openBook(tester);
      expect(find.byType(ReaderProgressLine), findsOneWidget);
      await openAa(tester);
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is AppSwitch && w.semanticLabel == 'Tampilin garis progres',
        ),
      );
      await tester.pumpAndSettle();
      expect(settings.prefs.showProgressLine, isFalse);
      expect(find.byType(ReaderProgressLine), findsNothing);
    });

    testWidgets('status bar hides with the capsules unless turned off', (
      tester,
    ) async {
      final overlays = <List<Object?>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setEnabledSystemUIOverlays') {
            overlays.add(call.arguments as List<Object?>);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      bool statusBar() => overlays.last.contains('SystemUiOverlay.top');

      await openBook(
        tester,
        readerBook: tallBook,
        saved: (chapterId: 13, paragraphIndex: 12, paragraphOffset: 0.0),
      );
      await tester.tapAt(const Offset(10, 800)); // margin: hide
      await tester.pumpAndSettle();
      expect(statusBar(), isFalse);
      await tester.tapAt(const Offset(10, 800)); // show
      await tester.pumpAndSettle();
      expect(statusBar(), isTrue);

      await settings.saveReaderPrefs(
        settings.prefs.copyWith(hideStatusBar: false),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 800)); // hide capsules only
      await tester.pumpAndSettle();
      expect(statusBar(), isTrue);
    });

    testWidgets('changing the size keeps the top line in place', (
      tester,
    ) async {
      await openBook(
        tester,
        readerBook: tallBook,
        saved: (chapterId: 13, paragraphIndex: 12, paragraphOffset: 0.4),
      );

      /// The paragraph crossing the top edge and how far into it the edge is.
      (int, double) topSpot() {
        for (var i = 0; i < 30; i++) {
          final f = find.textContaining('Tall $i:');
          if (f.evaluate().isEmpty) continue;
          final r = tester.getRect(f);
          if (r.top <= 0 && r.bottom > 0) return (i, -r.top / r.height);
        }
        fail('no paragraph at the top');
      }

      final before = topSpot();
      await openAa(tester);
      await tester.tap(find.bySemanticsLabel('Gedein huruf'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Gedein huruf'));
      await tester.pumpAndSettle();
      final after = topSpot();
      expect(after.$1, before.$1);
      expect(after.$2, closeTo(before.$2, 0.02));
    });

    testWidgets('narrow margin: the outer 8pt of the column is empty space', (
      tester,
    ) async {
      await openBook(
        tester,
        readerBook: tallBook,
        saved: (chapterId: 13, paragraphIndex: 12, paragraphOffset: 0.0),
        prefs: const ReaderPrefs(margin: TextMargin.narrow),
      );
      bool showing() => tester.getTopLeft(find.byType(ReaderTopCapsule)).dy > 0;
      final para = tester.getRect(find.textContaining('Tall 13:'));
      expect(para.left, 16);

      await tester.tapAt(Offset(para.left + 12, para.center.dy)); // text
      await tester.pumpAndSettle();
      expect(find.text('Artinya gini nih'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Tutup'));
      await tester.pumpAndSettle();
      expect(showing(), isFalse);

      final at = tester.getRect(find.textContaining('Tall 13:'));
      await tester.tapAt(Offset(at.left + 4, at.center.dy)); // edge
      await tester.pumpAndSettle();
      expect(showing(), isTrue);
      expect(find.byType(BottomSheet), findsNothing);
    });
  });

  Future<void> openToc(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Daftar isi'));
    await tester.pumpAndSettle();
  }

  testWidgets('contents sheet: header, current chapter, jump to another', (
    tester,
  ) async {
    await openBook(tester);
    await openToc(tester);
    expect(find.text('Daftar isi'), findsOneWidget);
    expect(find.textContaining('The Enchiridion · 2 bab · '), findsOneWidget);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('Lagi dibaca'), findsOneWidget);

    await tester.tap(find.text('II').last);
    await tester.pumpAndSettle();
    expect(find.text('Daftar isi'), findsNothing);
    expect(find.text('Bab 2'), findsOneWidget);
    expect(progress.saves.last, (
      chapterId: 11,
      paragraphIndex: 0,
      paragraphOffset: 0.0,
    ));
  });

  testWidgets('closing the contents keeps the chapter', (tester) async {
    await openBook(tester);
    await openToc(tester);
    progress.saves.clear();
    await tester.tap(find.bySemanticsLabel('Tutup'));
    await tester.pumpAndSettle();
    expect(find.text('Bab 1'), findsOneWidget);
    expect(progress.saves, isEmpty);
  });

  testWidgets('contents: capsule stays above the sheet, its button toggles', (
    tester,
  ) async {
    await openBook(tester);
    final button = find.byWidgetPredicate(
      (w) => w is CircleButton && w.semanticLabel == 'Daftar isi',
    );
    expect(tester.widget<CircleButton>(button).active, isFalse);
    final buttonCenter = tester.getCenter(button);

    await openToc(tester);
    expect(tester.widget<CircleButton>(button).active, isTrue); // yellow
    final capsule = tester.getRect(find.byType(ReaderTopCapsule));
    final sheet = tester.getRect(find.byType(BottomSheet));
    expect(capsule.top, greaterThanOrEqualTo(0)); // still showing
    expect(sheet.top, greaterThan(capsule.bottom)); // no overlap

    await tester.tapAt(buttonCenter);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.widget<CircleButton>(button).active, isFalse);
    expect(find.text('Bab 1'), findsOneWidget);
  });

  testWidgets('a long contents list scrolls to the current chapter', (
    tester,
  ) async {
    final many = ReaderBook(
      id: 1,
      title: 'Big Book',
      totalChars: 6000,
      chapters: [
        for (var i = 0; i < 60; i++)
          ChapterInfo(
            id: 100 + i,
            title: 'Chapter ${i + 1}',
            charOffset: i * 100,
            chars: 100,
          ),
      ],
    );
    paragraphs[140] = [p(0, ParagraphType.paragraph, 'Deep in the book.', 0)];
    await openBook(
      tester,
      readerBook: many,
      saved: (chapterId: 140, paragraphIndex: 0, paragraphOffset: 0.0),
    );
    await openToc(tester);
    final badge = find.text('Lagi dibaca');
    expect(badge, findsOneWidget);
    final sheet = tester.getRect(find.byType(BottomSheet));
    final row = tester.getRect(badge);
    expect(sheet.contains(row.center), isTrue); // scrolled into view
  });

  testWidgets('while the text loads, only the heading shows (no end card)', (
    tester,
  ) async {
    final pending = Completer<List<ReaderParagraph>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(FakeSettings()),
          readerBookProvider.overrideWith((ref, id) async => book),
          readingProgressRepositoryProvider.overrideWithValue(FakeProgress()),
          chapterParagraphsProvider.overrideWith((ref, id) => pending.future),
          translatedGroupsProvider.overrideWith(
            (ref, id) => Stream.value(translated[id] ?? const {}),
          ),
          chapterTranslatedProvider.overrideWith((ref, id) async => 0),
        ],
        child: MaterialApp(
          theme: stabiloTheme(Brightness.light),
          home: const ReaderView(bookId: 1),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Bab 1'), findsOneWidget);
    expect(find.text('Lanjut, gas'), findsNothing);

    double opacity() => tester
        .widget<AnimatedOpacity>(
          find.ancestor(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;
    expect(opacity(), 0); // hidden until loaded and in place

    pending.complete(paragraphs[10]!);
    await tester.pumpAndSettle();
    expect(find.text('Lanjut, gas'), findsOneWidget);
    expect(opacity(), 1);
  });

  const longBook = ReaderBook(
    id: 1,
    title: 'The Enchiridion',
    totalChars: 3000,
    chapters: [
      ChapterInfo(id: 10, title: 'I', charOffset: 0, chars: 100),
      ChapterInfo(id: 12, title: 'XXXIII', charOffset: 100, chars: 2900),
    ],
  );

  testWidgets('opening marks the book opened and starts at chapter 1', (
    tester,
  ) async {
    await openBook(tester);
    expect(progress.opened, [1]);
    expect(find.text('Bab 1'), findsOneWidget);
  });

  testWidgets('reopens at the saved chapter and paragraph', (tester) async {
    await openBook(
      tester,
      readerBook: longBook,
      saved: (chapterId: 12, paragraphIndex: 20, paragraphOffset: 0.0),
    );
    expect(find.text('Bab 2'), findsOneWidget);
    // A third down the screen, so there's context above it.
    final line = tester.getTopLeft(find.text('Line 20 of a long chapter.')).dy;
    expect(line, closeTo(1600 / 3, 1));
  });

  /// Where [spot] sits on screen: paragraph top + offset × its height.
  double spotY(WidgetTester tester, ReadingPosition spot) {
    final rect = tester.getRect(
      find.textContaining('Tall ${spot.paragraphIndex}:'),
    );
    return rect.top + spot.paragraphOffset * rect.height;
  }

  testWidgets('save → close → reopen lands on the same point', (tester) async {
    await openBook(
      tester,
      readerBook: tallBook,
      saved: (chapterId: 13, paragraphIndex: 0, paragraphOffset: 0.0),
    );
    progress.saves.clear();
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -1234),
    );
    await tester.pumpAndSettle();
    expect(progress.saves, isEmpty); // not on every frame, not right away
    await tester.pump(const Duration(milliseconds: 500));
    expect(progress.saves, hasLength(1));
    final saved = progress.saves.single;
    expect(saved.paragraphOffset, inExclusiveRange(0, 1));
    // The saved point is where the reading area starts.
    final top = tester.getTopLeft(find.byType(SingleChildScrollView)).dy;
    expect(spotY(tester, saved), closeTo(top, 1));

    await leave(tester);
    await openBook(tester, readerBook: tallBook, saved: saved);
    expect(spotY(tester, saved), closeTo(1600 / 3, 1));

    // Leaving without scrolling keeps the same spot.
    await leave(tester);
    expect(progress.saves.last, saved);
  });

  for (final scale in [1.0, 1.6]) {
    testWidgets('a bigger font keeps the paragraph and fraction (x$scale)', (
      tester,
    ) async {
      // Straight into the reader: the shelf isn't part of this.
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const saved = (chapterId: 13, paragraphIndex: 12, paragraphOffset: 0.4);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(FakeSettings()),
            readerBookProvider.overrideWith((ref, id) async => tallBook),
            readingProgressRepositoryProvider.overrideWithValue(
              FakeProgress(saved),
            ),
            chapterParagraphsProvider.overrideWith(
              (ref, id) async => paragraphs[id]!,
            ),
            translatedGroupsProvider.overrideWith(
              (ref, id) => Stream.value(translated[id] ?? const {}),
            ),
            chapterTranslatedProvider.overrideWith((ref, id) async => 0),
          ],
          child: MaterialApp(
            theme: stabiloTheme(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const ReaderView(bookId: 1),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(spotY(tester, saved), closeTo(1600 / 3, 1));
    });
  }

  testWidgets('the last paragraph of a chapter restores without overshoot', (
    tester,
  ) async {
    const saved = (chapterId: 13, paragraphIndex: 29, paragraphOffset: 0.9);
    await openBook(tester, readerBook: tallBook, saved: saved);
    expect(find.textContaining('Tall 29:'), findsOneWidget);
    final rect = tester.getRect(find.textContaining('Tall 29:'));
    expect(rect.top, inInclusiveRange(0, 1600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a one-paragraph chapter restores in place', (tester) async {
    const saved = (chapterId: 11, paragraphIndex: 0, paragraphOffset: 0.5);
    await openBook(tester, saved: saved);
    expect(
      find.text('Never say of anything, "I have lost it."'),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel('Balik ke rak'));
    await tester.pumpAndSettle();
    expect(progress.saves.last, saved);
  });

  testWidgets('a saved chapter that no longer exists falls back to chapter 1', (
    tester,
  ) async {
    await openBook(
      tester,
      saved: (chapterId: 999, paragraphIndex: 3, paragraphOffset: 0.0),
    );
    expect(find.text('Bab 1'), findsOneWidget);
  });

  testWidgets('scrolling saves the top paragraph once it stops', (
    tester,
  ) async {
    await openBook(
      tester,
      readerBook: longBook,
      saved: (chapterId: 12, paragraphIndex: 0, paragraphOffset: 0.0),
    );
    progress.saves.clear();
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    final last = progress.saves.last;
    expect(last.chapterId, 12);
    expect(last.paragraphIndex, greaterThan(5));
    // The saved paragraph is the one at the top of the reading area.
    final top = tester.getTopLeft(find.byType(SingleChildScrollView)).dy;
    final rect = tester.getRect(
      find.text('Line ${last.paragraphIndex} of a long chapter.'),
    );
    expect(rect.bottom, greaterThan(top));
  });

  testWidgets('moving to the next chapter and leaving both save', (
    tester,
  ) async {
    await openBook(tester);
    await tester.tap(find.text('Lanjut, gas'));
    await tester.pumpAndSettle();
    expect(progress.saves.last, (
      chapterId: 11,
      paragraphIndex: 0,
      paragraphOffset: 0.0,
    ));

    progress.saves.clear();
    await tester.tap(find.bySemanticsLabel('Balik ke rak'));
    await tester.pumpAndSettle();
    expect(progress.saves.last.chapterId, 11);
  });

  group('capsules', () {
    /// Drags by [dy] (negative = read on), holds still so there's no fling,
    /// then lets go. The touch slop (which scrolls too) goes the other way
    /// first, so only [dy] counts in its direction.
    Future<void> scrollBy(WidgetTester tester, double dy) async {
      final g = await tester.startGesture(const Offset(450, 800));
      await g.moveBy(Offset(0, -dy.sign * (kTouchSlop + 1)));
      await tester.pump();
      await g.moveBy(Offset(0, dy));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await g.up();
      await tester.pumpAndSettle();
    }

    double capsuleTop(WidgetTester tester) =>
        tester.getTopLeft(find.byType(ReaderTopCapsule)).dy;

    Future<void> openMiddle(WidgetTester tester) => openBook(
      tester,
      readerBook: tallBook,
      saved: (chapterId: 13, paragraphIndex: 12, paragraphOffset: 0.0),
    );

    testWidgets('down ≥ 24 hides, less snaps back', (tester) async {
      await openMiddle(tester);
      expect(capsuleTop(tester), 6); // safe area 0 + 6
      await scrollBy(tester, -18);
      expect(capsuleTop(tester), 6);
      await scrollBy(tester, -30);
      expect(capsuleTop(tester), lessThan(-capsuleHeight));
    });

    testWidgets('up ≥ 12 shows again, less stays hidden', (tester) async {
      await openMiddle(tester);
      await scrollBy(tester, -60);
      expect(capsuleTop(tester), lessThan(-capsuleHeight));
      await scrollBy(tester, 8);
      expect(capsuleTop(tester), lessThan(-capsuleHeight));
      await scrollBy(tester, 16);
      expect(capsuleTop(tester), 6);
    });

    testWidgets('follows the finger while dragging, then snaps', (
      tester,
    ) async {
      await openMiddle(tester);
      final g = await tester.startGesture(const Offset(450, 800));
      await g.moveBy(const Offset(0, -(kTouchSlop + 1)));
      await tester.pump();
      await g.moveBy(const Offset(0, -40));
      await tester.pump();
      expect(capsuleTop(tester), inExclusiveRange(-60, 6)); // part way
      await tester.pump(const Duration(milliseconds: 200));
      await g.up();
      await tester.pumpAndSettle();
      expect(capsuleTop(tester), lessThan(-capsuleHeight));
    });

    testWidgets('the start of a chapter keeps them showing', (tester) async {
      await openBook(tester, readerBook: tallBook);
      await tester.tap(find.text('Lanjut, gas'));
      await tester.pumpAndSettle();
      await scrollBy(tester, -40); // still inside the first 80pt
      expect(capsuleTop(tester), 6);
    });

    testWidgets('the end of a chapter brings them back', (tester) async {
      await openMiddle(tester);
      await scrollBy(tester, -60);
      expect(capsuleTop(tester), lessThan(-capsuleHeight));
      await tester.fling(
        find.byType(SingleChildScrollView),
        const Offset(0, -6000),
        3000,
      );
      await tester.pumpAndSettle();
      expect(capsuleTop(tester), 6);
      expect(find.text('Bab 2 beres'), findsOneWidget);
    });

    testWidgets('the text does not move when they hide', (tester) async {
      await openMiddle(tester);
      await scrollBy(tester, -60);
      final y = tester.getTopLeft(find.textContaining('Tall 14:')).dy;
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getTopLeft(find.textContaining('Tall 14:')).dy, y);
    });
  });

  group('tap zones', () {
    bool capsulesShowing(WidgetTester tester) =>
        tester.getTopLeft(find.byType(ReaderTopCapsule)).dy > 0;

    testWidgets('a paragraph is not empty space; the margin is', (
      tester,
    ) async {
      await openBook(
        tester,
        readerBook: tallBook,
        saved: (chapterId: 13, paragraphIndex: 12, paragraphOffset: 0.0),
      );
      expect(capsulesShowing(tester), isTrue);

      // Anywhere on a paragraph, even past the end of a short last line,
      // opens Artinya (and the capsules step aside).
      final para = tester.getRect(find.textContaining('Tall 13:'));
      await tester.tapAt(para.bottomRight - const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('Artinya gini nih'), findsOneWidget);
      expect(capsulesShowing(tester), isFalse);
      await tester.tap(find.bySemanticsLabel('Tutup'));
      await tester.pumpAndSettle();

      // Left margin, next to the same paragraph: capsules back.
      final at = tester.getRect(find.textContaining('Tall 13:'));
      await tester.tapAt(Offset(10, at.center.dy));
      await tester.pumpAndSettle();
      expect(capsulesShowing(tester), isTrue);
      expect(find.byType(BottomSheet), findsNothing);

      // The gap between two paragraphs hides them again.
      final next = tester.getRect(find.textContaining('Tall 14:'));
      await tester.tapAt(Offset(450, (at.bottom + next.top) / 2));
      await tester.pumpAndSettle();
      expect(capsulesShowing(tester), isFalse);
    });

    testWidgets('below the last text is empty space too', (tester) async {
      await openBook(tester);
      await tester.tap(find.text('Lanjut, gas'));
      await tester.pumpAndSettle();
      // Chapter II is one paragraph and its end card; the rest is empty.
      await tester.tapAt(const Offset(450, 1500));
      await tester.pumpAndSettle();
      expect(capsulesShowing(tester), isFalse);
    });
  });

  group('continue reading', () {
    const saved = (chapterId: 13, paragraphIndex: 12, paragraphOffset: 0.0);

    /// Straight into the reader, stopping right after the restore so the
    /// greeting can be watched frame by frame.
    Future<void> openReader(WidgetTester tester, {bool reduced = false}) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      if (reduced) {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
      }
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(FakeSettings()),
            readerBookProvider.overrideWith((ref, id) async => tallBook),
            readingProgressRepositoryProvider.overrideWithValue(
              FakeProgress(saved),
            ),
            chapterParagraphsProvider.overrideWith(
              (ref, id) async => paragraphs[id]!,
            ),
            translatedGroupsProvider.overrideWith(
              (ref, id) => Stream.value(translated[id] ?? const {}),
            ),
            chapterTranslatedProvider.overrideWith((ref, id) async => 0),
          ],
          child: MaterialApp(
            theme: stabiloTheme(Brightness.light),
            home: const ReaderView(bookId: 1),
          ),
        ),
      );
      await tester.pump(); // book + position
      await tester.pump(); // paragraphs
      await tester.pump(); // restore (post-frame)
    }

    Finder mark() => find.bySemanticsLabel('Terakhir lo baca di sini');
    double flashAlpha(WidgetTester tester) {
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: mark(), matching: find.byType(DecoratedBox)),
      );
      return (box.decoration as BoxDecoration).color!.a;
    }

    testWidgets('capsules show for 2.5 s, then hide', (tester) async {
      await openReader(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.getTopLeft(find.byType(ReaderTopCapsule)).dy, 6);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byType(ReaderTopCapsule)).dy,
        lessThan(-capsuleHeight),
      );
    });

    testWidgets('the saved group flashes once: 0 → peak → 0 in 1.2 s', (
      tester,
    ) async {
      await openReader(tester);
      // Past the content fade-in (semantics come with it), still before the
      // flash starts rising.
      await tester.pump(const Duration(milliseconds: 50));
      expect(mark(), findsOneWidget);
      final group = tester.getRect(mark());
      expect(
        group.contains(tester.getCenter(find.textContaining('Tall 12:'))),
        isTrue,
      );
      expect(flashAlpha(tester), 0);
      await tester.pump(const Duration(milliseconds: 450));
      expect(flashAlpha(tester), closeTo(0.62, 0.01)); // light flash, 62%
      await tester.pump(const Duration(milliseconds: 750));
      expect(mark(), findsNothing); // once, not looping
    });

    testWidgets('reduced motion: a left bar for 3 s instead of a flash', (
      tester,
    ) async {
      await openReader(tester, reduced: true);
      expect(mark(), findsOneWidget);
      expect(
        find.descendant(of: mark(), matching: find.byType(AnimatedBuilder)),
        findsNothing,
      );
      final bar = tester.getSize(
        find.descendant(of: mark(), matching: find.byType(Container)),
      );
      expect(bar.width, 4);
      await tester.pump(const Duration(milliseconds: 2900));
      expect(mark(), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(mark(), findsNothing);
    });

    testWidgets('a fresh book gets no greeting', (tester) async {
      await openBook(tester, readerBook: tallBook);
      expect(mark(), findsNothing);
    });
  });

  group('edge fade', () {
    EdgeFadeScroll fade(WidgetTester tester) => tester.widget<EdgeFadeScroll>(
      find.descendant(
        of: find.byType(ReaderView),
        matching: find.byType(EdgeFadeScroll),
      ),
    );

    /// Mask opacity down the screen, edges fully on.
    List<double> mask(WidgetTester tester) => edgeFadeStops(
      1600,
      top: fade(tester).top,
      bottom: fade(tester).bottom,
      topOn: 1,
      bottomOn: 1,
    ).alphas;

    Future<void> open(WidgetTester tester) async {
      tester.view.padding = const FakeViewPadding(top: 54, bottom: 34);
      await openBook(
        tester,
        readerBook: tallBook,
        saved: (chapterId: 13, paragraphIndex: 12, paragraphOffset: 0.0),
      );
    }

    testWidgets('capsules: empty status bar, 18% behind them to the edge', (
      tester,
    ) async {
      await open(tester);
      expect(
        fade(tester).top,
        const EdgeFadeSide(48, clear: 54, hold: 64, floor: 0.18),
      );
      // No empty band under the progress line: 18% right down to the edge.
      expect(
        fade(tester).bottom,
        const EdgeFadeSide(48, hold: 34 + 14 + 40, floor: 0.18),
      );
      expect(mask(tester).first, 0); // status bar
      expect(mask(tester).last, closeTo(0.18, 1e-9)); // bottom edge
    });

    testWidgets('immersive: no fade anywhere', (tester) async {
      await open(tester);
      await tester.tapAt(const Offset(10, 800)); // margin: hide
      await tester.pumpAndSettle();
      expect(mask(tester).every((a) => a == 1), isTrue);
    });

    testWidgets('the strength follows the capsule animation', (tester) async {
      await open(tester);
      await tester.tapAt(const Offset(10, 800));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100)); // mid-animation
      expect(fade(tester).bottom.floor, inExclusiveRange(0.18, 1));
      expect(fade(tester).top.clearAlpha, inExclusiveRange(0, 1));
    });
  });

  group('Artinya', () {
    Future<void> openTall(WidgetTester tester) => openBook(
      tester,
      readerBook: tallBook,
      saved: (chapterId: 13, paragraphIndex: 12, paragraphOffset: 0.0),
    );

    Future<void> tapGroup(WidgetTester tester, int i) async {
      await tester.tap(find.textContaining('Tall $i:'));
      await tester.pumpAndSettle();
    }

    final block = find.byKey(const ValueKey('open-group'));
    double pixels(WidgetTester tester) => tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;

    testWidgets('loading, then the translation and meaning', (tester) async {
      final pending = Completer<AiReply>();
      answer = (_) => pending.future;
      await openTall(tester);
      await tester.tap(find.textContaining('Tall 13:'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Bentar, lagi mikir...'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(ReaderTopCapsule)).dy,
        lessThan(0),
      ); // capsules hide

      pending.complete(replyFor((chapterId: 13, groupIndex: 13)));
      await tester.pumpAndSettle();
      expect(find.text('Artinya gini nih'), findsOneWidget);
      expect(find.text('TERJEMAHAN'), findsOneWidget);
      expect(find.textContaining('ID Tall 13:'), findsOneWidget);
      expect(find.text('Makna grup 13.'), findsOneWidget);
      // The section chips wrap their text, they do not span the sheet.
      final sheetWidth = tester.getSize(find.byType(BottomSheet)).width;
      final pills = find.descendant(
        of: find.byType(Tag),
        matching: find.byType(Container),
      );
      expect(pills, findsNWidgets(2));
      for (final pill in pills.evaluate()) {
        expect(
          tester.getSize(find.byWidget(pill.widget)).width,
          lessThan(sheetWidth / 2),
        );
      }
    });

    testWidgets('the group sits 16pt above the sheet, highlighted', (
      tester,
    ) async {
      await openTall(tester);
      await tapGroup(tester, 13);
      expect(block, findsOneWidget);
      final sheetTop = tester.getTopLeft(find.byType(BottomSheet)).dy;
      expect(tester.getRect(block).bottom, closeTo(sheetTop - 16, 1));
      // Highlight reaches half the margin out: 24 / 2.
      expect(tester.getRect(block).left, 12);
    });

    testWidgets('a group too tall to fit: its top goes under the safe area', (
      tester,
    ) async {
      const hugeBook = ReaderBook(
        id: 1,
        title: 'The Enchiridion',
        totalChars: 3000,
        chapters: [
          ChapterInfo(id: 10, title: 'I', charOffset: 0, chars: 100),
          ChapterInfo(id: 14, title: 'Huge', charOffset: 100, chars: 2900),
        ],
      );
      await openBook(
        tester,
        readerBook: hugeBook,
        saved: (chapterId: 14, paragraphIndex: 0, paragraphOffset: 0.0),
      );
      await tester.tap(find.textContaining('Huge:'));
      await tester.pumpAndSettle();
      expect(tester.getRect(block).top, closeTo(0 + 16, 1)); // safe area 0
    });

    testWidgets('one group: closing goes back to where you were', (
      tester,
    ) async {
      await openTall(tester);
      final before = pixels(tester);
      await tapGroup(tester, 13);
      expect(pixels(tester), isNot(closeTo(before, 1)));
      await tester.tap(find.bySemanticsLabel('Tutup'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(pixels(tester), closeTo(before, 1));
      expect(block, findsNothing);
    });

    testWidgets('after "Lanjut": the next group, and the page stays', (
      tester,
    ) async {
      await openTall(tester);
      await tapGroup(tester, 13);
      await tester.tap(find.text('Lanjut'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ID Tall 14:'), findsOneWidget);
      final sheetTop = tester.getTopLeft(find.byType(BottomSheet)).dy;
      expect(tester.getRect(block).bottom, closeTo(sheetTop - 16, 1));
      final at = pixels(tester);
      progress.saves.clear();

      await tester.tap(find.bySemanticsLabel('Tutup'));
      await tester.pumpAndSettle();
      expect(pixels(tester), closeTo(at, 1));
      await tester.pump(const Duration(milliseconds: 500));
      expect(progress.saves, isNotEmpty); // new spot remembered
    });

    testWidgets('the last group of a chapter has no "Lanjut"', (tester) async {
      await openTall(tester);
      await tester.fling(
        find.byType(SingleChildScrollView),
        const Offset(0, -6000),
        3000,
      );
      await tester.pumpAndSettle();
      await tapGroup(tester, 29);
      final lanjut = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Lanjut'),
      );
      expect(lanjut.onPressed, isNull);
    });

    testWidgets('error: code, then "Coba lagi" asks again', (tester) async {
      var calls = 0;
      answer = (g) async {
        calls++;
        if (calls == 1) throw const AiException(AiError.timeout);
        return replyFor(g);
      };
      await openTall(tester);
      await tapGroup(tester, 13);
      expect(find.text('Yah, gagal nih'), findsOneWidget);
      expect(find.text('timeout · 30 detik'), findsOneWidget);
      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(find.text('Artinya gini nih'), findsOneWidget);
      expect(calls, 2);
    });

    testWidgets('out of credits says so', (tester) async {
      answer = (_) async => throw const AiException(AiError.http, status: 402);
      await openTall(tester);
      await tapGroup(tester, 13);
      expect(find.text('HTTP 402 · saldo abis'), findsOneWidget);
    });

    testWidgets('no API key: asks for one, "Nanti aja" closes', (tester) async {
      answer = (_) async => throw const AiException(AiError.noApiKey);
      await openTall(tester);
      await tapGroup(tester, 13);
      expect(find.text('Isi API key dulu yuk'), findsOneWidget);
      expect(find.text('openrouter.ai/keys'), findsNothing); // inside a span
      expect(find.textContaining('openrouter.ai/keys'), findsOneWidget);
      await tester.tap(find.text('Nanti aja'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('copy puts the whole translation on the clipboard', (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await openTall(tester);
      await tapGroup(tester, 13);
      await tester.tap(find.text('Salin'));
      await tester.pump();
      await tester.pump();
      expect(copied, startsWith('ID Tall 13:'));
      expect(find.text('Disalin'), findsOneWidget);
      expect(find.text('Udah disalin, tinggal paste'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Udah disalin, tinggal paste'), findsNothing);
    });

    testWidgets('translated groups get a mark in the margin', (tester) async {
      translated = {
        13: {12, 14},
      };
      await openTall(tester);
      final mark = find.byKey(const ValueKey('mark-12'));
      expect(mark, findsOneWidget);
      expect(find.byKey(const ValueKey('mark-13')), findsNothing);
      final rect = tester.getRect(mark);
      expect(rect.width, 4);
      expect(rect.left, 10); // centred on 12pt into the 24pt margin
      final para = tester.getRect(find.textContaining('Tall 12:'));
      expect(rect.top, closeTo(para.top + 5, 1));
    });
  });
}
