import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/reading_progress_repository.dart';
import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/domain/ai_prompt.dart';
import 'package:luma/domain/models/reader_prefs.dart';
import 'package:luma/domain/models/ai_reply.dart';
import 'package:luma/domain/models/book.dart';
import 'package:luma/main.dart';
import 'package:luma/ui/core/theme/reader_typography.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/core/theme/stabilo_tokens.dart';
import 'package:luma/ui/core/theme/stabilo_type.dart';
import 'package:luma/ui/core/widgets/sheet.dart';
import 'package:luma/ui/core/widgets/book_card.dart';
import 'package:luma/ui/core/widgets/buttons.dart';
import 'package:luma/ui/core/widgets/edge_fade.dart';
import 'package:luma/ui/core/widgets/switch.dart';
import 'package:luma/ui/features/bookshelf/view_models/bookshelf_view_model.dart';
import 'package:luma/ui/features/bookshelf/views/bookshelf_view.dart';
import 'package:luma/ui/core/widgets/tag.dart';
import 'package:luma/ui/features/reader/view_models/breakdown_view_model.dart';
import 'package:luma/ui/features/reader/view_models/reader_view_model.dart';
import 'package:luma/ui/features/reader/views/reader_capsule.dart';
import 'package:luma/ui/features/reader/views/reader_view.dart';
import 'package:luma/ui/features/breakdown/views/breakdown_view.dart';
import 'package:luma/domain/breakdown_prompt.dart';
import 'package:luma/domain/models/breakdown.dart';

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

const groupedBook = ReaderBook(
  id: 1,
  title: 'The Enchiridion',
  totalChars: 3000,
  chapters: [
    ChapterInfo(id: 10, title: 'I', charOffset: 0, chars: 100),
    ChapterInfo(id: 15, title: 'Grouped', charOffset: 100, chars: 2900),
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

/// Sections of a group's saved breakdown (0 = none).
var brokenDown = <GroupRef, int>{};

/// What the AI says for a group; tests swap it.
late Future<AiReply> Function(GroupRef) answer;

/// The sheet's source, like `groupAiStreamProvider`: waiting (placeholders
/// sized from the group's paragraphs), then [answer] as a cached result or a
/// failure. Streaming tests leave [answer] pending and [FakeAiStream.push]
/// states through [streams].
final streams = <GroupRef, FakeAiStream>{};

class FakeAiStream extends GroupAiStream {
  FakeAiStream(super.group);

  @override
  AiStream build() {
    // `this.`: flutter_test's top-level group() shadows the inherited field.
    streams[this.group] = this;
    answer(this.group).then(
      (r) {
        if (ref.mounted) {
          state = AiStream(
            phase: AiPhase.done,
            draft: AiDraft(translations: r.translations, meaning: r.meaning),
            cached: true,
          );
        }
      },
      onError: (Object e) {
        if (ref.mounted) {
          state = AiStream(phase: AiPhase.failed, error: e as AiException);
        }
      },
    );
    return AiStream(sources: sourcesFor(this.group));
  }

  void push(AiStream next) => state = next;
}

List<int> sourcesFor(GroupRef g) => [
  for (final p in paragraphs[g.chapterId]!)
    if (p.groupIndex == g.groupIndex) p.text.length,
];

AiReply replyFor(GroupRef g) => AiReply(
  translations: [
    for (final p in paragraphs[g.chapterId]!)
      if (p.groupIndex == g.groupIndex) 'ID ${p.text}',
  ],
  meaning: 'Makna grup ${g.groupIndex}.',
);

/// One group (1) of three tall paragraphs between filler: taller than the room
/// above the sheet, so its text has to scroll inside the card.
final grouped = [
  for (var i = 0; i < 12; i++)
    p(i, ParagraphType.paragraph, 'Before $i: ${'word ' * 30}'.trim(), 0),
  for (final (i, name) in ['Alpha', 'Bravo', 'Charlie'].indexed)
    p(12 + i, ParagraphType.paragraph, '$name: ${'word ' * 60}'.trim(), 1),
  for (var i = 0; i < 12; i++)
    p(15 + i, ParagraphType.paragraph, 'After $i: ${'word ' * 30}'.trim(), 2),
];

final paragraphs = {
  15: grouped,
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
    brokenDown = {};
    FakeBreakdown.reset();
    streams.clear();
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
          groupAiStreamProvider.overrideWith2(FakeAiStream.new),
          breakdownStreamProvider.overrideWith2(FakeBreakdown.new),
          breakdownSectionsProvider.overrideWith(
            (ref, g) async => brokenDown[g] ?? 0,
          ),
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

  testWidgets('time read before moving on goes to the chapter just left', (
    tester,
  ) async {
    await openBook(tester);
    // ReadingClock reads the real clock; testWidgets' clock is fake.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.tap(find.text('Lanjut, gas'));
    await tester.pumpAndSettle();

    expect(progress.readingSeconds, greaterThanOrEqualTo(1));
    // The short chapter 1 is fully on screen: chapter 1, ending at its end
    // (offset 0 + 100 chars), not chapter 2 (starts at 100).
    expect(progress.spans, hasLength(1));
    expect(progress.spans.single.chapterId, 10);
    expect(progress.spans.single.endChar, 100);
  });

  testWidgets('only the book end screen marks the book finished', (
    tester,
  ) async {
    await openBook(tester);
    await tester.tap(find.text('Lanjut, gas'));
    await tester.pumpAndSettle();
    expect(find.text('Itu tadi bab terakhir!'), findsOneWidget);
    expect(progress.finished, isEmpty); // last chapter, not past it yet

    await tester.tap(find.text('Lanjut, gas'));
    await tester.pumpAndSettle();
    expect(find.text('kelar!'), findsOneWidget);
    expect(progress.finished, [1]);
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

    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      testWidgets(
        'status bar hides with the capsules unless turned off ($platform)',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          // true = system bars visible after each call. iOS: overlay list;
          // Android: edgeToEdge shows them, immersiveSticky hides them.
          final shown = <bool>[];
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'SystemChrome.setEnabledSystemUIOverlays') {
                shown.add(
                  (call.arguments as List<Object?>).contains(
                    'SystemUiOverlay.top',
                  ),
                );
              }
              if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
                shown.add(call.arguments == 'SystemUiMode.edgeToEdge');
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          bool statusBar() => shown.last;

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
          // Reset inside the body: flutter_test checks this before tearDown.
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }

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
    final sheetBox = find.byKey(const ValueKey('meaning-sheet'));
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
      final sheetWidth = tester.getSize(sheetBox).width;
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

    testWidgets('on open the group starts at the safe area, highlighted', (
      tester,
    ) async {
      await openTall(tester);
      await tapGroup(tester, 13);
      expect(block, findsOneWidget);
      expect(tester.getRect(block).top, closeTo(0, 1)); // safe area 0
      // Highlight reaches half the margin out: 24 / 2.
      expect(tester.getRect(block).left, 12);
    });

    testWidgets('a group too tall to fit: its top is at the safe area', (
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
      expect(tester.getRect(block).top, closeTo(0, 1)); // safe area 0
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
      expect(sheetBox, findsNothing);
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
      final sheetTop = tester.getTopLeft(sheetBox).dy;
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

    Text sheetText(WidgetTester tester, String s) => tester.widget<Text>(
      find.descendant(of: sheetBox, matching: find.textContaining(s)),
    );

    testWidgets('the sheet text follows the Aa prefs, UI text does not', (
      tester,
    ) async {
      const prefs = ReaderPrefs(
        font: ReadingFont.book,
        sizeStep: 6,
        spacing: LineSpacing.loose,
        margin: TextMargin.wide,
      );
      await openBook(
        tester,
        readerBook: tallBook,
        saved: (chapterId: 13, paragraphIndex: 12, paragraphOffset: 0.0),
        prefs: prefs,
      );
      final page = tester.getTopLeft(find.textContaining('Tall 12:')).dx;
      await tapGroup(tester, 13);

      final want = ReaderTypography(prefs, Brightness.light).style;
      for (final s in ['ID Tall 13:', 'Makna grup 13.']) {
        final style = sheetText(tester, s).style!;
        expect(style.fontFamily, want.fontFamily);
        expect(style.fontSize, 24);
        expect(style.height, want.height);
        // Same left edge as the page text (margin Lega 32).
        expect(tester.getTopLeft(find.textContaining(s)).dx, page);
      }
      expect(page, 32);
      // Title and chips stay UI-sized.
      expect(
        sheetText(tester, 'Artinya gini nih').style!.fontSize,
        StabiloType.titleMd.fontSize,
      );
      expect(tester.getTopLeft(find.text('Artinya gini nih')).dx, 24);
    });

    testWidgets('a narrow margin stays at the sheet padding (24)', (
      tester,
    ) async {
      await openBook(
        tester,
        readerBook: tallBook,
        saved: (chapterId: 13, paragraphIndex: 12, paragraphOffset: 0.0),
        prefs: const ReaderPrefs(margin: TextMargin.narrow),
      );
      await tapGroup(tester, 13);
      expect(tester.getTopLeft(find.textContaining('ID Tall 13:')).dx, 24);
    });

    testWidgets('changing Aa while the sheet is open updates the text', (
      tester,
    ) async {
      await openTall(tester);
      await tapGroup(tester, 13);
      expect(sheetText(tester, 'ID Tall 13:').style!.fontSize, 18.5);

      await settings.saveReaderPrefs(settings.prefs.copyWith(sizeStep: 6));
      await tester.pumpAndSettle();
      expect(find.text('Artinya gini nih'), findsOneWidget);
      expect(sheetText(tester, 'ID Tall 13:').style!.fontSize, 24);
    });

    testWidgets('loading placeholder rows use the Aa line height', (
      tester,
    ) async {
      const prefs = ReaderPrefs(sizeStep: 6, spacing: LineSpacing.loose);
      answer = (_) => Completer<AiReply>().future;
      await openBook(
        tester,
        readerBook: tallBook,
        saved: (chapterId: 13, paragraphIndex: 12, paragraphOffset: 0.0),
        prefs: prefs,
      );
      await tester.tap(find.textContaining('Tall 13:'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final extent = ReaderTypography(prefs, Brightness.light).lineExtent;
      // Skeleton rows for both paragraphs and the meaning, each as tall as
      // one text line.
      final rows = find.byWidgetPredicate(
        (w) =>
            w is SizedBox &&
            (w.height ?? 0) - extent < 1e-6 &&
            (w.height ?? 0) - extent > -1e-6,
      );
      expect(rows, findsAtLeastNWidgets(4));
    });

    AiReply longReply(GroupRef g) => AiReply(
      translations: [for (var i = 0; i < 40; i++) 'ID line $i ${'word ' * 20}'],
      meaning: 'Makna panjang.',
    );

    Finder sheetScroll() => find.descendant(
      of: sheetBox,
      matching: find.byType(SingleChildScrollView),
    );

    /// A finger moving in 20pt steps with a frame in between, like a real one.
    Future<void> slowDrag(WidgetTester tester, double dy) async {
      final g = await tester.startGesture(tester.getCenter(sheetScroll()));
      for (var moved = 0.0; moved.abs() < dy.abs(); moved += 20 * dy.sign) {
        await g.moveBy(Offset(0, 20 * dy.sign));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();
    }

    testWidgets('the card stays put, its text follows the translation read', (
      tester,
    ) async {
      answer = (g) async => AiReply(
        translations: [
          for (final n in ['satu', 'dua', 'tiga']) 'ID $n ${'kata ' * 200}',
        ],
        meaning: 'Makna panjang.',
      );
      await openBook(
        tester,
        readerBook: groupedBook,
        saved: (chapterId: 15, paragraphIndex: 12, paragraphOffset: 0.0),
      );
      await tester.tap(find.textContaining('Bravo:').first);
      await tester.pumpAndSettle();
      final sheetTop = tester.getTopLeft(sheetBox).dy;
      final pinned = find.byKey(const ValueKey('pinned-group'));
      Rect card() => tester.getRect(pinned);
      Rect inCard(String name) => tester.getRect(
        find.descendant(of: pinned, matching: find.textContaining('$name:')),
      );

      // First open: the card starts at the safe area (0 in tests), its text at
      // the start, and it runs on under the sheet.
      final start = card();
      expect(start.top, closeTo(0, 1));
      expect(start.bottom, closeTo(sheetTop, 1));
      expect(inCard('Alpha').top, closeTo(start.top + 8, 1));

      // Reading to the end: the card does not move, Charlie comes into view
      // 24pt above the sheet.
      await slowDrag(tester, -4000);
      expect(card(), start);
      expect(inCard('Charlie').bottom, closeTo(sheetTop - 24, 1));
      expect(inCard('Alpha').top, lessThan(start.top));

      // Back up to the first translation: the text is where it opened.
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: sheetScroll(), matching: find.byType(Scrollable)),
      );
      await slowDrag(tester, scroll.position.pixels - 20);
      expect(card(), start);
      // 20pt short of the very top: progress is almost, not exactly, zero.
      expect(inCard('Alpha').top, closeTo(start.top + 8, 3));

      // Closing: the card goes away, the page was never moved by the follow.
      await tester.tap(find.bySemanticsLabel('Tutup'));
      await tester.pumpAndSettle();
      expect(pinned, findsNothing);
    });

    testWidgets('one long paragraph: its text scrolls inside the card', (
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
      answer = (g) async => AiReply(
        translations: ['ID Huge ${'kata ' * 400}'],
        meaning: 'Makna panjang.',
      );
      await openBook(
        tester,
        readerBook: hugeBook,
        saved: (chapterId: 14, paragraphIndex: 0, paragraphOffset: 0.0),
      );
      await tester.tap(find.textContaining('Huge:').first);
      await tester.pumpAndSettle();
      final sheetTop = tester.getTopLeft(sheetBox).dy;
      final pinned = find.byKey(const ValueKey('pinned-group'));
      Rect text() => tester.getRect(
        find.descendant(of: pinned, matching: find.textContaining('Huge:')),
      );
      final start = tester.getRect(pinned);
      final at = text().top;
      expect(start.top, closeTo(0, 1));

      // Half way through the translation: the text moved up by about half.
      await slowDrag(tester, -300);
      expect(tester.getRect(pinned), start); // the card itself stays
      expect(text().top, lessThan(at));
      final half = text().top;

      // To the end: the last line of the paragraph sits above the sheet.
      await slowDrag(tester, -4000);
      expect(text().top, lessThan(half));
      expect(text().bottom, closeTo(sheetTop - 24, 1));

      // Closing: the pinned card goes the moment the sheet starts down, so what
      // shows under the sheet is the page's own card, not a second copy.
      await tester.tap(find.bySemanticsLabel('Tutup'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(sheetBox, findsOneWidget);
      expect(pinned, findsNothing);
      await tester.pumpAndSettle();
      expect(pinned, findsNothing);
    });

    testWidgets('height is fixed at 528 of 844 in every state', (tester) async {
      await openTall(tester);
      final want = tester.view.physicalSize.height * Layout.artinyaHeight;
      await tapGroup(tester, 13);
      expect(tester.getSize(sheetBox).height, closeTo(want, 1)); // short
      await tester.tap(find.bySemanticsLabel('Tutup'));
      await tester.pumpAndSettle();

      answer = (g) async => longReply(g);
      await tapGroup(tester, 13);
      expect(tester.getSize(sheetBox).height, closeTo(want, 1)); // long
      await tester.tap(find.bySemanticsLabel('Tutup'));
      await tester.pumpAndSettle();

      answer = (_) async => throw const AiException(AiError.timeout);
      await tapGroup(tester, 13);
      expect(tester.getSize(sheetBox).height, closeTo(want, 1)); // error
      // Buttons stick to the bottom even with little content.
      expect(
        tester.getBottomLeft(find.text('Coba lagi')).dy,
        lessThan(tester.getBottomLeft(sheetBox).dy),
      );
    });

    double lanjutTop(WidgetTester tester) =>
        tester.getTopLeft(find.text('Lanjut')).dy;
    double titleBottom(WidgetTester tester) =>
        tester.getBottomLeft(find.text('Artinya gini nih')).dy;
    double sheetBottom(WidgetTester tester) =>
        tester.getBottomLeft(sheetBox).dy;
    bool buttonsShown(WidgetTester tester) =>
        lanjutTop(tester) < sheetBottom(tester);
    bool headerShown(WidgetTester tester) =>
        titleBottom(tester) > tester.getTopLeft(sheetBox).dy;

    Future<void> openLong(WidgetTester tester) async {
      answer = (g) async => longReply(g);
      await openTall(tester);
      await tapGroup(tester, 13);
    }

    testWidgets(
      'scrolling down hides the header and the buttons, grabber stays',
      (tester) async {
        await openLong(tester);
        final grabber = tester.getTopLeft(find.byType(SheetGrabber)).dy;
        expect(grabber, tester.getTopLeft(sheetBox).dy + 10);
        expect(headerShown(tester) && buttonsShown(tester), isTrue);

        await tester.drag(sheetScroll(), const Offset(0, -300));
        await tester.pumpAndSettle();
        expect(headerShown(tester), isFalse);
        expect(buttonsShown(tester), isFalse);
        expect(tester.getTopLeft(find.byType(SheetGrabber)).dy, grabber);
      },
    );

    testWidgets(
      'the buttons need 24pt down to hide, the header leaves with the text',
      (tester) async {
        await openLong(tester);
        await tester.drag(sheetScroll(), const Offset(0, -20));
        await tester.pumpAndSettle();
        expect(buttonsShown(tester), isTrue); // under 24
        await tester.drag(sheetScroll(), const Offset(0, -30));
        await tester.pumpAndSettle();
        expect(buttonsShown(tester), isFalse);
      },
    );

    testWidgets('scrolling up 12pt or more brings both back', (tester) async {
      await openLong(tester);
      await tester.drag(sheetScroll(), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(buttonsShown(tester) || headerShown(tester), isFalse);

      await tester.drag(sheetScroll(), const Offset(0, 80));
      await tester.pumpAndSettle();
      expect(buttonsShown(tester), isTrue);
      expect(headerShown(tester), isTrue);
    });

    testWidgets('a half-way header snaps to the nearest end on release', (
      tester,
    ) async {
      await openLong(tester);
      await tester.drag(sheetScroll(), const Offset(0, -400));
      await tester.pumpAndSettle();
      // Up 30: the header follows the finger a third of the way: snaps hidden.
      await tester.drag(sheetScroll(), const Offset(0, 30));
      await tester.pumpAndSettle();
      expect(headerShown(tester), isFalse);
      expect(buttonsShown(tester), isTrue);
    });

    testWidgets('hitting the bottom shows the buttons, the header stays away', (
      tester,
    ) async {
      await openLong(tester);
      await tester.drag(sheetScroll(), const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.fling(sheetScroll(), const Offset(0, -3000), 8000);
      await tester.pumpAndSettle();
      expect(buttonsShown(tester), isTrue);
      expect(headerShown(tester), isFalse);
    });

    testWidgets('back at the very top, everything is there again', (
      tester,
    ) async {
      await openLong(tester);
      await tester.drag(sheetScroll(), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.drag(sheetScroll(), const Offset(0, 400)); // back to 0
      await tester.pumpAndSettle();
      expect(headerShown(tester), isTrue);
      expect(buttonsShown(tester), isTrue);
    });

    EdgeFadeScroll sheetFade(WidgetTester tester) => tester.widget(
      find.descendant(of: sheetBox, matching: find.byType(EdgeFadeScroll)),
    );

    testWidgets('the fades follow the chrome: header, grabber, buttons', (
      tester,
    ) async {
      await openLong(tester);
      var f = sheetFade(tester);
      // Everything visible: top fade under the header (y 75), bottom fade
      // right above the buttons (86 of buttons + safe area).
      expect(f.top, const EdgeFadeSide(20, clear: 75));
      expect(f.bottom, const EdgeFadeSide(20, clear: 86));

      await tester.drag(sheetScroll(), const Offset(0, -400));
      await tester.pumpAndSettle();
      f = sheetFade(tester);
      // Header away: fade under the grabber (from y 12). Buttons away:
      // edge-to-edge, no bottom fade at all.
      expect(f.top, const EdgeFadeSide(20, clear: 12));
      expect(f.bottom, const EdgeFadeSide(0));

      await tester.drag(sheetScroll(), const Offset(0, 80));
      await tester.pumpAndSettle();
      f = sheetFade(tester);
      expect(f.top, const EdgeFadeSide(20, clear: 75));
      expect(f.bottom, const EdgeFadeSide(20, clear: 86));
    });

    testWidgets(
      'fade edges: none at the top, both mid-way, bottom gone at the end',
      (tester) async {
        await openLong(tester);
        EdgeFadeScrollState edges() => tester.state(
          find.descendant(of: sheetBox, matching: find.byType(EdgeFadeScroll)),
        );
        expect(edges().debugEdges, (top: false, bottom: true));
        await tester.drag(sheetScroll(), const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(edges().debugEdges, (top: true, bottom: true));
        await tester.fling(sheetScroll(), const Offset(0, -3000), 8000);
        await tester.pumpAndSettle();
        expect(edges().debugEdges, (top: true, bottom: false));
      },
    );

    testWidgets('programmatic scroll never hides the chrome', (tester) async {
      await openLong(tester);
      tester
          .state<ScrollableState>(
            find.descendant(of: sheetBox, matching: find.byType(Scrollable)),
          )
          .position
          .jumpTo(400);
      await tester.pumpAndSettle();
      expect(buttonsShown(tester), isTrue);
      expect(headerShown(tester), isTrue);
    });

    testWidgets('content that fits never hides anything', (tester) async {
      await openTall(tester);
      await tapGroup(tester, 13);
      await tester.drag(sheetScroll(), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(buttonsShown(tester), isTrue);
      expect(headerShown(tester), isTrue);
    });

    testWidgets('error and loading states never hide', (tester) async {
      final pending = Completer<AiReply>();
      answer = (_) => pending.future;
      await openTall(tester);
      await tester.tap(find.textContaining('Tall 13:'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.drag(sheetScroll(), const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Lagi mikir'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Lanjut')).dy,
        lessThan(sheetBottom(tester)),
      );
    });

    testWidgets('VoiceOver on: the chrome never hides', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await openLong(tester);
      await tester.drag(sheetScroll(), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(buttonsShown(tester), isTrue);
      expect(find.bySemanticsLabel('Tutup'), findsOneWidget);
    });

    testWidgets('reduce motion: no slide, just a fade', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await openLong(tester);
      final top = lanjutTop(tester);
      double opacityOf(Finder f) => tester
          .widget<Opacity>(
            find.ancestor(of: f, matching: find.byType(Opacity)).first,
          )
          .opacity;
      expect(opacityOf(find.text('Lanjut')), 1);

      await tester.drag(sheetScroll(), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(lanjutTop(tester), top); // did not move
      expect(opacityOf(find.text('Lanjut')), 0);
      expect(opacityOf(find.text('Artinya gini nih')), 0);

      await tester.drag(sheetScroll(), const Offset(0, 80));
      await tester.pumpAndSettle();
      expect(opacityOf(find.text('Lanjut')), 1);
      expect(opacityOf(find.text('Artinya gini nih')), 1);
    });

    testWidgets('swipe down on the content at offset 0 closes the sheet', (
      tester,
    ) async {
      answer = (g) async => longReply(g);
      await openTall(tester);
      await tapGroup(tester, 13);
      await tester.fling(sheetScroll(), const Offset(0, 300), 2000);
      await tester.pumpAndSettle();
      expect(find.text('Artinya gini nih'), findsNothing);
    });

    testWidgets('swipe down on the grabber closes the sheet, at any offset', (
      tester,
    ) async {
      await openLong(tester);
      await tester.drag(sheetScroll(), const Offset(0, -300)); // not at top
      await tester.pumpAndSettle();
      await tester.drag(find.byType(SheetGrabber), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(find.text('Artinya gini nih'), findsNothing);
    });

    testWidgets('a short swipe on the grabber springs back', (tester) async {
      await openLong(tester);
      final top = tester.getTopLeft(sheetBox).dy;
      await tester.drag(find.byType(SheetGrabber), const Offset(0, 40));
      await tester.pumpAndSettle();
      expect(find.text('Artinya gini nih'), findsOneWidget);
      expect(tester.getTopLeft(sheetBox).dy, closeTo(top, 1));
    });

    testWidgets('tapping the empty area above the sheet closes it only', (
      tester,
    ) async {
      await openLong(tester);
      await tester.tapAt(const Offset(450, 100));
      await tester.pumpAndSettle();
      expect(find.text('Artinya gini nih'), findsNothing);
      // The tap was the barrier's: the capsules stay away.
      expect(tester.getTopLeft(find.byType(ReaderTopCapsule)).dy, lessThan(0));
    });

    testWidgets('tapping the text inside the sheet does not close it', (
      tester,
    ) async {
      await openLong(tester);
      await tester.tap(find.textContaining('ID line 0'));
      await tester.pumpAndSettle();
      expect(find.text('Artinya gini nih'), findsOneWidget);
    });

    testWidgets('a small pull at offset 0 springs back', (tester) async {
      answer = (g) async => longReply(g);
      await openTall(tester);
      await tapGroup(tester, 13);
      final top = tester.getTopLeft(sheetBox).dy;
      await tester.drag(sheetScroll(), const Offset(0, 40));
      await tester.pumpAndSettle();
      expect(find.text('Artinya gini nih'), findsOneWidget);
      expect(tester.getTopLeft(sheetBox).dy, closeTo(top, 1));
    });

    testWidgets('swipe down below offset 0 scrolls back, sheet stays', (
      tester,
    ) async {
      answer = (g) async => longReply(g);
      await openTall(tester);
      await tapGroup(tester, 13);
      final top = tester.getTopLeft(sheetBox).dy;
      await tester.drag(sheetScroll(), const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.drag(sheetScroll(), const Offset(0, 100));
      await tester.pumpAndSettle();
      expect(find.text('Artinya gini nih'), findsOneWidget);
      expect(tester.getTopLeft(sheetBox).dy, closeTo(top, 1));
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

    // Tile: 52 tall, top at 31. Text starts at 31 + 52 + 24 = 107.
    for (final (name, error, title) in [
      ('error', const AiException(AiError.timeout), 'Yah, gagal nih'),
      ('no-key', const AiException(AiError.noApiKey), 'Isi API key dulu yuk'),
    ]) {
      testWidgets('$name text sits 24pt below the icon tile', (tester) async {
        answer = (_) async => throw error;
        await openTall(tester);
        await tapGroup(tester, 13);
        expect(
          tester.getTopLeft(find.text(title)).dy -
              tester.getTopLeft(sheetBox).dy,
          107,
        );
      });
    }

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
      expect(sheetBox, findsNothing);
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

    group('Bedahin entry', () {
      const g = (chapterId: 13, groupIndex: 13);
      final entry = find.text('Masih bingung? Bedahin');

      Future<void> openEntry(WidgetTester tester) async {
        await openTall(tester);
        await tapGroup(tester, 13);
        await tester.scrollUntilVisible(
          find.textContaining('Per bagian'),
          200,
          scrollable: find.descendant(
            of: sheetBox,
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
      }

      testWidgets('last item of the sheet; opens Bedahin over the sheet', (
        tester,
      ) async {
        FakeBreakdown.initial = BreakdownState(
          phase: BreakdownPhase.done,
          input: BreakdownInput(
            book: (title: 'The Enchiridion', author: null, chapter: 'Tall'),
            chapters: const ['I', 'Tall'],
            chapter: 2,
            original: const ['Tall 13'],
            translations: const ['ID Tall 13.'],
            meaning: 'M',
          ),
          draft: const Breakdown(
            sections: [
              BreakdownSection(from: 1, to: 1, meaning: 'A.', logic: 'B.'),
            ],
          ),
          cached: true,
        );
        await openEntry(tester);
        expect(entry, findsOneWidget);
        // After the meaning, inside the scrolling content.
        expect(
          tester.getTopLeft(entry).dy,
          greaterThan(tester.getTopLeft(find.text('Makna grup 13.')).dy),
        );

        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(find.byType(BreakdownView), findsOneWidget);
        expect(FakeBreakdown.live.keys, [g]);
        expect(find.text('Udah dibedah nih'), findsOneWidget);

        // Back: the sheet is still there.
        await leave(tester);
        expect(find.byType(BreakdownView), findsNothing);
        expect(sheetBox, findsOneWidget);
        expect(entry, findsOneWidget);

        // "Balik baca": the screen and the sheet close together.
        await tester.tap(entry);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Balik baca'));
        await tester.pumpAndSettle();
        expect(find.byType(BreakdownView), findsNothing);
        expect(sheetBox, findsNothing);
        expect(find.byType(ReaderView), findsOneWidget);
        expect(find.textContaining('Tall 13:'), findsOneWidget);
      });

      testWidgets('already broken down: "Buka bedahan" with its count', (
        tester,
      ) async {
        brokenDown[g] = 4;
        await openTall(tester);
        await tapGroup(tester, 13);
        await tester.scrollUntilVisible(
          find.text('Buka bedahan'),
          200,
          scrollable: find.descendant(
            of: sheetBox,
            matching: find.byType(Scrollable),
          ),
        );
        expect(find.text('Udah pernah dibedah · 4 bagian'), findsOneWidget);
        expect(entry, findsNothing);
      });
    });

    group('streaming', () {
      const g = (chapterId: 13, groupIndex: 13);

      /// Opens group 13 with the answer pending; the test pushes states.
      Future<FakeAiStream> openStreaming(
        WidgetTester tester, {
        ReaderPrefs prefs = const ReaderPrefs(),
      }) async {
        answer = (_) => Completer<AiReply>().future;
        await openBook(
          tester,
          readerBook: tallBook,
          saved: (chapterId: 13, paragraphIndex: 12, paragraphOffset: 0.0),
          prefs: prefs,
        );
        await tester.tap(find.textContaining('Tall 13:'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        return streams[g]!;
      }

      AiStream state(
        AiPhase phase, {
        List<String> translations = const [],
        String? meaning,
      }) => AiStream(
        phase: phase,
        draft: AiDraft(translations: translations, meaning: meaning),
        sources: sourcesFor(g),
      );

      Future<void> frames(WidgetTester tester, [int n = 60]) async {
        for (var i = 0; i < n; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      /// The translation text widget (plain or with a faded tail).
      Text translation(WidgetTester tester, String start) =>
          tester.widget<Text>(
            find.byWidgetPredicate(
              (w) =>
                  w is Text &&
                  (w.data ?? w.textSpan?.toPlainText() ?? '').startsWith(start),
            ),
          );
      String plain(Text t) => t.data ?? t.textSpan!.toPlainText();

      double sheetPixels(WidgetTester tester) => tester
          .state<ScrollableState>(
            find.descendant(of: sheetBox, matching: find.byType(Scrollable)),
          )
          .position
          .pixels;

      AppButton button(WidgetTester tester, String label) =>
          tester.widget<AppButton>(find.widgetWithText(AppButton, label));

      final long = 'Kata ${'panjang sekali ' * 300}akhir.';

      testWidgets('waiting: placeholders, status on Salin, Lanjut off', (
        tester,
      ) async {
        await openStreaming(tester);
        expect(find.text('Bentar, lagi mikir...'), findsOneWidget);
        expect(find.text('Lagi mikir'), findsOneWidget);
        expect(find.text('Salin'), findsNothing);
        expect(
          find.bySemanticsLabel('Salin, belum bisa: lagi mikir'),
          findsOne,
        );
        expect(find.bySemanticsLabel('Batalin'), findsOneWidget); // the X
        expect(button(tester, 'Lanjut').onPressed, isNull);
      });

      testWidgets('text comes out paced, the tail fades, then goes solid', (
        tester,
      ) async {
        final s = await openStreaming(tester);
        const full =
            'Halo semua, ini terjemahan yang lumayan panjang buat ngetes ritme.';
        s.push(state(AiPhase.translating, translations: [full]));
        await tester.pump();
        await frames(tester, 30);
        expect(find.text('Artinya gini nih'), findsOneWidget);
        expect(find.text('Lagi nulis'), findsOneWidget);
        final partial = translation(tester, 'Halo');
        expect(plain(partial).length, inInclusiveRange(4, full.length - 1));
        // The last 4 words fade 80 · 60 · 42 · 26%.
        final spans = (partial.textSpan! as TextSpan).children!
            .cast<TextSpan>();
        expect(spans, hasLength(5));
        expect(spans.last.style!.color!.a, closeTo(0.26, 0.01));
        expect(spans[1].style!.color!.a, closeTo(0.8, 0.01));

        s.push(
          state(AiPhase.done, translations: [full], meaning: 'Gitu maknanya.'),
        );
        await frames(tester, 40); // drain ≤ 600 ms
        await tester.pump(Motion.tailFade);
        await tester.pump(Motion.statusSwap);
        final done = translation(tester, 'Halo');
        expect(done.data, full); // solid, no faded spans
        expect(find.text('Gitu maknanya.'), findsOneWidget);
        expect(button(tester, 'Salin').onPressed, isNotNull);
        expect(find.bySemanticsLabel('Tutup'), findsOneWidget);
      });

      testWidgets('no scrolling until the first text comes', (tester) async {
        final s = await openStreaming(tester);
        await tester.drag(sheetScroll(), const Offset(0, -200));
        await tester.pump();
        expect(sheetPixels(tester), 0);
        expect(
          sheetBox,
          findsOneWidget,
        ); // a drag down does not close it either

        s.push(state(AiPhase.translating, translations: [long]));
        await frames(tester, 30);
        await tester.drag(sheetScroll(), const Offset(0, -200));
        await frames(tester, 20);
        expect(sheetPixels(tester), greaterThan(0));
      });

      testWidgets('stays at the start while writing; buttons never hide', (
        tester,
      ) async {
        final s = await openStreaming(tester);
        s.push(state(AiPhase.translating, translations: [long]));
        await frames(tester, 120);
        expect(sheetPixels(tester), 0); // no auto-scroll: read from the top
        expect(find.text('Ke bawah'), findsNothing);
        await tester.drag(sheetScroll(), const Offset(0, -200));
        await frames(tester, 20);
        expect(buttonsShown(tester), isTrue);
      });

      testWidgets('slow: a card on top, gone once tokens come', (tester) async {
        final s = await openStreaming(tester);
        s.push(state(AiPhase.slow));
        await tester.pump();
        expect(find.text('Agak lama nih...'), findsOneWidget);
        expect(find.text('Bentar, lagi mikir...'), findsOneWidget);
        // Status leaves the button; the card explains.
        expect(find.text('Salin'), findsOneWidget);
        expect(button(tester, 'Salin').onPressed, isNull);

        s.push(state(AiPhase.translating, translations: ['Akhirnya.']));
        await tester.pump();
        expect(find.text('Agak lama nih...'), findsNothing);
      });

      testWidgets('slow: "Coba lagi" starts over', (tester) async {
        final s = await openStreaming(tester);
        s.push(state(AiPhase.slow));
        await tester.pump();
        await tester.tap(find.text('Coba lagi'));
        await tester.pump();
        expect(find.text('Agak lama nih...'), findsNothing);
        expect(find.text('Lagi mikir'), findsOneWidget);
      });

      testWidgets('cut: text kept, placeholders dropped, banner retries', (
        tester,
      ) async {
        final s = await openStreaming(tester);
        s.push(state(AiPhase.translating, translations: ['Halo, ini baru']));
        await frames(tester, 5);
        s.push(state(AiPhase.cut, translations: ['Halo, ini baru setengah']));
        await tester.pump();
        await tester.pump();
        expect(find.text('Yah, kepotong di tengah'), findsOneWidget);
        expect(translation(tester, 'Halo').data, 'Halo, ini baru setengah');
        expect(find.text('Maksud penulisnya tuh...'), findsNothing);
        expect(button(tester, 'Salin').onPressed, isNull);
        expect(find.text('Masih bingung? Bedahin'), findsNothing);

        await tester.tap(find.text('Coba lagi'));
        await tester.pump();
        expect(find.text('Yah, kepotong di tengah'), findsNothing);
        expect(find.text('Bentar, lagi mikir...'), findsOneWidget);
      });

      testWidgets('Bedahin entry waits for the whole meaning, then fades in', (
        tester,
      ) async {
        final s = await openStreaming(tester);
        s.push(state(AiPhase.meaning, translations: ['Halo.'], meaning: 'Mak'));
        await frames(tester, 30);
        expect(find.text('Masih bingung? Bedahin'), findsNothing);
        s.push(state(AiPhase.done, translations: ['Halo.'], meaning: 'Makna.'));
        await frames(tester, 90);
        expect(find.text('Masih bingung? Bedahin'), findsOneWidget);
      });

      testWidgets('"Lanjut" is off until done or cut; the X closes', (
        tester,
      ) async {
        final s = await openStreaming(tester);
        s.push(state(AiPhase.translating, translations: ['Halo']));
        await frames(tester, 5);
        expect(button(tester, 'Lanjut').onPressed, isNull);
        await tester.tap(find.text('Lanjut'));
        await tester.pump();
        expect(streams.keys, isNot(contains((chapterId: 13, groupIndex: 14))));

        s.push(state(AiPhase.cut, translations: ['Halo']));
        await tester.pump();
        expect(button(tester, 'Lanjut').onPressed, isNotNull);

        await tester.tap(find.bySemanticsLabel('Tutup'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(sheetBox, findsNothing);
      });

      testWidgets('the X cancels mid-stream', (tester) async {
        final s = await openStreaming(tester);
        s.push(state(AiPhase.translating, translations: ['Halo']));
        await frames(tester, 5);
        await tester.tap(find.bySemanticsLabel('Batalin'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(sheetBox, findsNothing);
      });

      testWidgets('placeholders follow Aa: bigger text, more rows', (
        tester,
      ) async {
        int rows(ReaderPrefs prefs) {
          final extent = ReaderTypography(prefs, Brightness.light).lineExtent;
          return find
              .byWidgetPredicate(
                (w) =>
                    w is SizedBox &&
                    ((w.height ?? 0) - extent).abs() < 1e-6 &&
                    w.child is Align,
              )
              .evaluate()
              .length;
        }

        await openStreaming(tester);
        final small = rows(const ReaderPrefs());
        const big = ReaderPrefs(
          sizeStep: 6,
          font: ReadingFont.book,
          margin: TextMargin.wide,
        );
        await settings.saveReaderPrefs(big);
        await tester.pump();
        await tester.pump();
        expect(rows(big), greaterThan(small));
      });

      testWidgets('reduce motion: whole parts only, no fading tail', (
        tester,
      ) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        final s = await openStreaming(tester);
        s.push(state(AiPhase.translating, translations: ['Halo semua di']));
        await frames(tester, 5);
        expect(find.textContaining('Halo semua'), findsNothing); // not whole

        s.push(
          state(
            AiPhase.meaning,
            translations: ['Halo semua di sini.'],
            meaning: 'Mak',
          ),
        );
        await frames(tester, 5);
        expect(translation(tester, 'Halo').data, 'Halo semua di sini.');
        expect(find.textContaining('Mak'), findsNothing);
      });

      testWidgets('finishing keeps the scroll position', (tester) async {
        final s = await openStreaming(tester);
        s.push(state(AiPhase.translating, translations: [long]));
        await frames(tester, 120);
        await tester.drag(sheetScroll(), const Offset(0, -200));
        await frames(tester, 20);
        final before = sheetPixels(tester);
        expect(before, greaterThan(0));
        s.push(state(AiPhase.done, translations: [long], meaning: 'Makna.'));
        await frames(tester, 60);
        expect(sheetPixels(tester), before);
        expect(button(tester, 'Salin').onPressed, isNotNull);
      });
    });
  });
}
