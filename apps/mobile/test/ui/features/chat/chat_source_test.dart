import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:luma/data/repositories/reading_progress_repository.dart';
import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/domain/models/book.dart';
import 'package:luma/domain/models/book_chat.dart';
import 'package:luma/domain/models/reader_prefs.dart';
import 'package:luma/ui/core/theme/reader_typography.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/core/widgets/buttons.dart';
import 'package:luma/ui/core/widgets/sheet.dart';
import 'package:luma/ui/core/widgets/edge_fade.dart';
import 'package:luma/ui/features/chat/views/chat_source_sheet.dart';
import 'package:luma/ui/features/chat/views/chat_history.dart';
import 'package:luma/ui/features/chat/views/chat_source_visit_view.dart';
import 'package:luma/ui/features/reader/view_models/reader_view_model.dart';

import '../../../fakes.dart';

const request = (
  bookId: 1,
  sessionId: 2,
  turnId: 3,
  attempt: 1,
  sourceId: 'S1',
);
const readingBook = ReaderBook(
  id: 1,
  title: 'Stoic',
  totalChars: 9000,
  chapters: [
    ChapterInfo(id: 10, title: 'I', charOffset: 0, chars: 3000),
    ChapterInfo(id: 25, title: 'III', charOffset: 3000, chars: 6000),
  ],
);
final paragraphs = [
  for (var i = 0; i < 12; i++)
    ReaderParagraph(
      index: i,
      groupIndex: i,
      type: ParagraphType.paragraph,
      text: 'Paragraph $i: ${'philosophy ' * (i == 4 ? 200 : 20)}',
    ),
];
final source = ChatSource(
  id: 'S1',
  chapterTitle: 'III',
  anchors: [
    SourceAnchor(
      book: (bookId: 1, contentRevision: 1),
      chapterId: 25,
      paragraphIndex: 4,
      start: 80,
      end: paragraphs[4].text.length,
      paragraphHash: chatTextHash(paragraphs[4].text),
      snapshot: paragraphs[4].text.substring(80),
    ),
    SourceAnchor(
      book: (bookId: 1, contentRevision: 1),
      chapterId: 25,
      paragraphIndex: 5,
      start: 0,
      end: paragraphs[5].text.length,
      paragraphHash: chatTextHash(paragraphs[5].text),
      snapshot: paragraphs[5].text,
    ),
  ],
);

void main() {
  late FakeProgress progress;
  late FakeSettings settings;
  late StreamController<ChatSourceLocation?> locations;
  late GoRouter router;
  var now = DateTime(2026, 10, 30);

  Future<void> open(
    WidgetTester t, {
    bool sheet = false,
    Brightness brightness = Brightness.light,
    bool available = true,
    ReaderPrefs prefs = const ReaderPrefs(),
  }) async {
    progress = FakeProgress((
      chapterId: 10,
      paragraphIndex: 2,
      paragraphOffset: .4,
    ));
    settings = FakeSettings(prefs);
    locations = StreamController<ChatSourceLocation?>.broadcast();
    addTearDown(() => unawaited(locations.close()));
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () {
                if (sheet) {
                  showChatSourceSheet(
                    context,
                    request: request,
                    snapshot: source,
                  );
                } else {
                  context.push('/visit');
                }
              },
              child: const Text('Open source'),
            ),
          ),
        ),
        GoRoute(
          path: '/visit',
          builder: (_, _) => const ChatSourceVisitView(request: request),
        ),
      ],
    );
    addTearDown(router.dispose);
    t.view.physicalSize = const Size(900, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          chatSourceProvider(request).overrideWith((ref) async* {
            yield ChatSourceLocation(source: source, available: available);
            yield* locations.stream;
          }),
          readerNowProvider.overrideWithValue(() => now),
          readingProgressRepositoryProvider.overrideWithValue(progress),
          settingsRepositoryProvider.overrideWithValue(settings),
          readerBookProvider(1).overrideWith((ref) async => readingBook),
          chapterParagraphsProvider.overrideWith((ref, id) async => paragraphs),
          translatedGroupsProvider.overrideWith((ref, id) => Stream.value({})),
          chapterTranslatedProvider.overrideWith((ref, id) async => 0),
        ],
        child: MaterialApp.router(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          theme: stabiloTheme(brightness),
          routerConfig: router,
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Open source'));
    await t.pumpAndSettle();
  }

  void unchanged() {
    expect(progress.opened, isEmpty);
    expect(progress.saves, isEmpty);
    expect(progress.finished, isEmpty);
    expect(progress.readingSeconds, 0);
    expect(progress.spans, isEmpty);
    expect(progress.saved, (
      chapterId: 10,
      paragraphIndex: 2,
      paragraphOffset: .4,
    ));
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'source visit is read only across chapter navigation/lifecycle/dispose $brightness',
      (t) async {
        await open(t, brightness: brightness);
        expect(find.text('III'), findsOneWidget);
        final marked = find.byKey(const ValueKey('source-paragraph-4'));
        expect(marked, findsOneWidget);
        final rect = t.getRect(marked);
        // A quote taller than the viewport starts below the top reader capsule.
        expect(rect.top, lessThan(200));
        expect(rect.bottom, greaterThan(t.view.physicalSize.height));
        expect(
          find.byKey(const ValueKey('source-paragraph-5')),
          findsOneWidget,
        );
        expect(find.text('Ngobrol'), findsNothing);
        unchanged();
        now = now.add(const Duration(minutes: 2));
        await t.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -600),
        );
        await t.pumpAndSettle();
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await t.pump();
        now = now.add(const Duration(minutes: 2));
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await t.pump();
        // Visit navigation reuses the reader's normal chapter advance handler.
        final end = find.text('Lanjut, gas');
        await t.ensureVisible(end);
        await t.pumpAndSettle();
        await t.tap(end);
        await t.pumpAndSettle();
        expect(find.text('Open source'), findsOneWidget);
        unchanged();
        await t.pumpWidget(const SizedBox());
        await t.pump();
        unchanged();
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'covered history keeps its pixels when a response grows and the source closes',
    (t) async {
      t.view.physicalSize = const Size(900, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final at = DateTime(2026, 10, 30);
      ChatTurn turn(int words) => ChatTurn(
        id: 1,
        sessionId: 2,
        book: (bookId: 1, contentRevision: 1),
        sequence: 1,
        question: 'Maknanya?',
        createdAt: at,
        updatedAt: at,
        phase: ChatPhase.writing,
        model: 'fake',
        promptVersion: 3,
        preview: [ChatAnswerBlock(text: 'Gagasan ' * words, sources: [])],
      );
      Future<void> pump({required bool suspended, required int words}) async {
        await t.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            theme: stabiloTheme(Brightness.light),
            home: Scaffold(
              body: ChatHistory(
                turns: [turn(words)],
                onAnchor: (_) {},
                suspended: suspended,
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
      }

      await pump(suspended: false, words: 1000);
      final scroll = t.state<ScrollableState>(find.byType(Scrollable).first);
      await t.tap(find.bySemanticsLabel('Ke terbaru'));
      await t.pumpAndSettle();
      final before = scroll.position.pixels;
      expect(before, greaterThan(0));
      await pump(suspended: true, words: 1500);
      expect(scroll.position.pixels, before);
      await pump(suspended: false, words: 1500);
      expect(scroll.position.pixels, before);
      expect(find.bySemanticsLabel('Ke terbaru'), findsOneWidget);
    },
  );

  testWidgets('large text leaves room for the source-visit header', (t) async {
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await open(t);
    final fade = t.widget<EdgeFadeScroll>(find.byType(EdgeFadeScroll).first);
    expect(fade.top.clear, greaterThan(32));
    expect(
      find.text('Lagi ngintip · progres masih I · Paragraf 3'),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'Aa and chapter navigation keep source identity without writing reading data',
    (t) async {
      await open(t);
      await settings.saveReaderPrefs(
        const ReaderPrefs(sizeStep: 6, font: ReadingFont.system),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('source-paragraph-4')), findsOneWidget);
      expect(find.bySemanticsLabel('Daftar isi'), findsNothing);
      expect(find.bySemanticsLabel('Atur tampilan teks'), findsNothing);
      expect(
        find.text('Lagi ngintip · progres masih I · Paragraf 3'),
        findsOneWidget,
      );
      unchanged();
      // System/swipe-back uses the same pop path without committing the visit.
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Open source'), findsOneWidget);
      unchanged();
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'source sheet scrolls metadata with full-width text in $brightness',
      (t) async {
        await open(t, sheet: true, brightness: brightness);
        final chapter = find.text('III · bagian 5 · bagian 6');
        final scroll = find.ancestor(
          of: chapter,
          matching: find.byType(SingleChildScrollView),
        );
        expect(scroll, findsOneWidget);
        expect(
          find.ancestor(
            of: find.bySemanticsLabel('Tutup'),
            matching: find.byType(SingleChildScrollView),
          ),
          findsNothing,
        );
        final text = find.byType(SelectableText);
        final sheetRect = t.getRect(find.byType(BottomSheet));
        final textRect = t.getRect(text);
        final paragraphRect = t.getRect(
          find.ancestor(of: chapter, matching: find.byType(Container)).first,
        );
        expect(paragraphRect.height, 26);
        expect(textRect.left - sheetRect.left, 24);
        expect(sheetRect.right - textRect.right, 24);
        expect(textRect.top - paragraphRect.bottom, 24);
        final button = find.byType(AppButton);
        expect(t.getRect(scroll), sheetRect);
        final fade = t.widget<EdgeFadeScroll>(find.byType(EdgeFadeScroll));
        expect(fade.top, const EdgeFadeSide(20, clear: 12));
        expect(fade.bottom, const EdgeFadeSide(20, clear: 86));
        expect(t.getRect(button).top, sheetRect.bottom - fade.bottom.clear);
        final padding =
            t.widget<SingleChildScrollView>(scroll).padding! as EdgeInsets;
        expect(padding.bottom - 52 - 34, 16);
        expect(t.getRect(find.byType(SheetGrabber)).top - sheetRect.top, 10);
        expect(sheetRect.bottom - t.getRect(button).bottom, 34);
        expect(t.getSize(text).width, t.getSize(scroll).width - 48);
        final chapterY = t.getTopLeft(chapter).dy;
        final buttonY = t.getTopLeft(find.text('Buka di buku')).dy;
        await t.drag(scroll, const Offset(0, -300));
        await t.pumpAndSettle();
        expect(t.getTopLeft(chapter).dy, lessThan(chapterY - 100));
        expect(t.getTopLeft(find.text('Buka di buku')).dy, buttonY);
        final edges = t.state<EdgeFadeScrollState>(find.byType(EdgeFadeScroll));
        expect(edges.debugEdges, (top: true, bottom: true));
        final position = t
            .state<ScrollableState>(
              find
                  .descendant(of: scroll, matching: find.byType(Scrollable))
                  .first,
            )
            .position;
        position.jumpTo(position.maxScrollExtent);
        await t.pumpAndSettle();
        expect(edges.debugEdges, (top: true, bottom: false));
        final message = find.byKey(const ValueKey('source-quote'));
        expect(
          t.getRect(button).top - t.getRect(message).bottom,
          closeTo(16, .1),
        );
        expect(t.takeException(), isNull);
        unchanged();
      },
    );
  }

  testWidgets('snapshot remains visible when stale; open action revoked', (
    t,
  ) async {
    await open(t, sheet: true);
    expect(find.text('Buka di buku'), findsOneWidget);
    expect(t.widget<AppButton>(find.byType(AppButton)).onPressed, isNotNull);
    locations.add(ChatSourceLocation(source: source, available: false));
    await t.pumpAndSettle();
    expect(find.textContaining('Sumber ini udah gak tersedia'), findsOneWidget);
    expect(find.byType(AppButton), findsNothing);
    expect(find.text('Bukunya udah berubah'), findsOneWidget);
    expect(find.text('Buka di buku'), findsNothing);
    expect(find.byType(SelectableText), findsOneWidget);
    unchanged();
    await t.tap(find.bySemanticsLabel('Tutup'));
    await t.pumpAndSettle();
    expect(find.text('Open source'), findsOneWidget);
  });

  testWidgets('source quote follows the Aa prefs', (t) async {
    const prefs = ReaderPrefs(font: ReadingFont.book, sizeStep: 6);
    await open(t, sheet: true, prefs: prefs);
    final quote = t.widget<SelectableText>(
      find.descendant(
        of: find.byKey(const ValueKey('source-quote')),
        matching: find.byType(SelectableText),
      ),
    );
    expect(quote.style!.fontFamily, readingFamily(ReadingFont.book));
    expect(quote.style!.fontSize, ReaderPrefs.sizes[6]);
  });

  for (final margin in TextMargin.values) {
    testWidgets('source sheet margin matches the reader for $margin', (
      t,
    ) async {
      final prefs = ReaderPrefs(margin: margin);
      await open(t, sheet: true, prefs: prefs);
      final sheetLeft = t.getTopLeft(find.byType(ChatSourceSheet)).dx;
      final quote = find.descendant(
        of: find.byKey(const ValueKey('source-quote')),
        matching: find.byType(SelectableText),
      );
      expect(t.getTopLeft(quote).dx - sheetLeft, prefs.marginWidth);
    });
  }

  testWidgets('deletion and restore cannot reactivate an existing visit', (
    t,
  ) async {
    await open(t);
    locations.add(null);
    await t.pumpAndSettle();
    expect(find.textContaining('Sumber ini udah gak tersedia'), findsOneWidget);
    locations.add(
      ChatSourceLocation(source: source, available: true, generation: Object()),
    );
    await t.pumpAndSettle();
    expect(find.textContaining('Sumber ini udah gak tersedia'), findsOneWidget);
    unchanged();
    await t.tap(find.text('Balik ke obrolan'));
    await t.pumpAndSettle();
    expect(find.text('Open source'), findsOneWidget);
  });
}
