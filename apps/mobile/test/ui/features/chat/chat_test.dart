import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:luma/domain/models/ai_reply.dart';
import 'package:luma/domain/chat_exploration.dart';
import 'package:luma/ui/features/chat/views/chat_copy.dart';
import 'package:luma/domain/models/book_chat.dart';
import 'package:luma/routing/router.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/core/widgets/buttons.dart';
import 'package:luma/ui/features/bookshelf/view_models/bookshelf_view_model.dart';
import 'package:luma/ui/features/chat/view_models/chat_view_model.dart';
import 'package:luma/ui/features/chat/views/chat_composer.dart';
import 'package:luma/ui/features/chat/views/chat_sessions_view.dart';
import 'package:luma/ui/features/chat/views/chat_view.dart';

const book = (bookId: 1, contentRevision: 1);
final now = DateTime(2026, 10, 28, 10);
ChatSession session(int id, {int bookId = 1, int revision = 1}) => ChatSession(
  id: id,
  book: (bookId: bookId, contentRevision: revision),
  title: 'Topik $id',
  manualTitle: false,
  createdAt: now,
  updatedAt: now,
  preview: 'Pertanyaan $id',
);
ChatTurn turn(
  int id, {
  ChatPhase phase = ChatPhase.done,
  ChatAnswer? answer,
  String? exploration,
}) => ChatTurn(
  id: id,
  sessionId: 1,
  book: book,
  sequence: id,
  question: 'Pertanyaan $id',
  createdAt: now,
  updatedAt: now,
  phase: phase,
  model: 'test',
  promptVersion: 1,
  draft: '{"secret raw JSON": true}',
  answer: answer,
  exploration: exploration,
);
final source = ChatSource(
  id: 'S1',
  chapterTitle: 'Bab I',
  anchors: [
    SourceAnchor(
      book: book,
      chapterId: 1,
      paragraphIndex: 0,
      start: 0,
      end: 5,
      paragraphHash: 'hash',
      snapshot: 'Bukti',
    ),
  ],
);
final answer = ChatAnswer(
  status: ChatAnswerStatus.answered,
  blocks: [
    ChatAnswerBlock(text: 'Jawaban tervalidasi.', sources: [source]),
  ],
);

class FakeChat extends ChatViewModel {
  FakeChat(super.bookId, this.initial);
  final ChatState initial;
  int sends = 0, stops = 0, creates = 0, launches = 0, continuations = 0;
  final opened = <int>[], deleted = <int>[];
  final renamed = <String>[];
  Completer<void>? stopGate;
  @override
  ChatState build() => initial;
  ChatState get current => state;
  void push(ChatState next) => state = next;
  @override
  void setDraft(String value) => state = state.copyWith(draft: value);
  @override
  void removeQuote() => state = state.copyWith(selectedQuote: null);
  @override
  void setScrollAnchor(ChatScrollAnchor anchor) =>
      state = state.copyWith(scrollAnchor: anchor);
  @override
  Future<void> send() async {
    if (state.canSend) {
      sends++;
      state = state.copyWith(draft: '', phase: ChatPhase.waiting);
    }
  }

  @override
  Future<void> continueExploration() async {
    if (!state.canContinue) return;
    continuations++;
    state = state.copyWith(phase: ChatPhase.retrieving);
  }

  @override
  Future<void> retry() async {
    sends++;
  }

  @override
  Future<void> stop() async {
    stops++;
    await stopGate?.future;
    state = state.copyWith(phase: ChatPhase.stopped);
  }

  @override
  Future<void> newSession() async {
    creates++;
    state = ChatState(book: book, loading: false);
  }

  @override
  Future<void> openSession(int id) async {
    opened.add(id);
    state = state.copyWith(activeSession: session(id));
  }

  @override
  Future<void> deleteSession(int id) async {
    deleted.add(id);
    state = state.copyWith(activeSession: null, turns: []);
  }

  @override
  Future<void> rename(String title) async {
    renamed.add(title);
  }

  @override
  Future<void> launch(ChatLaunchContext context) async {
    launches++;
  }
}

Finder button(String label) => find.byWidgetPredicate(
  (w) => w is CircleButton && w.semanticLabel == label,
);

void main() {
  late FakeChat vm;
  late GoRouter router;
  Future<void> open(
    WidgetTester tester, {
    ChatState? state,
    List<ChatSession>? sessions,
    String path = '/reader/1/chat',
    Size size = const Size(900, 1400),
    bool actualRouter = false,
    Object? extra,
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    vm = FakeChat(1, state ?? ChatState(book: book, loading: false));
    final container = ProviderContainer(
      overrides: [
        chatViewModelProvider(1).overrideWith(() => vm),
        booksStreamProvider.overrideWith((ref) => Stream.value([])),
        chatSessionsProvider(1)
            .overrideWith((ref) => Stream.value(sessions ?? [])),
      ],
    );
    addTearDown(container.dispose);
    if (actualRouter) {
      router = container.read(routerProvider);
      router.go(path, extra: extra);
    } else {
      router = GoRouter(
        initialLocation: path,
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('Home')),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, _) => const Scaffold(body: Text('Settings')),
          ),
          GoRoute(
            path: '/reader/:bookId/chat',
            builder: (_, _) => const ChatView(bookId: 1),
            routes: [
              GoRoute(
                path: 'sessions',
                builder: (_, _) => const ChatSessionsView(bookId: 1),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: stabiloTheme(Brightness.light),
          darkTheme: stabiloTheme(Brightness.dark),
          routerConfig: router,
          themeMode: themeMode,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('unfinished index progress never hides a terminal status', () {
    for (final phase in [
      ChatPhase.done,
      ChatPhase.failed,
      ChatPhase.cut,
      ChatPhase.stopped,
      ChatPhase.interrupted,
    ]) {
      expect(
        ChatState(
          phase: phase,
          indexProgress: (completed: 64, total: 100),
        ).indexLabel,
        isNull,
      );
    }
    expect(
      ChatState(
        phase: ChatPhase.slow,
        indexProgress: (completed: 100, total: 100),
      ).indexLabel,
      isNull,
    );
  });

  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'streaming paragraph, citations, final and failed draft in $theme',
      (t) async {
        final writing = turn(1, phase: ChatPhase.writing);
        await open(
          t,
          themeMode: theme,
          state: ChatState(
            book: book,
            loading: false,
            activeSession: session(1),
            turns: [writing],
            phase: ChatPhase.writing,
            preview: (
              attempt: writing.attemptRef,
              blocks: [ChatAnswerBlock(text: 'Jawaban tumbuh', sources: [])],
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('Jawaban tumbuh'), findsOneWidget);
        expect(find.text('Lagi nulis…'), findsOneWidget);
        expect(find.text('Bab I'), findsNothing);
        expect(find.textContaining('secret raw JSON'), findsNothing);
        vm.push(
          vm.current.copyWith(
            preview: (
              attempt: writing.attemptRef,
              blocks: [
                ChatAnswerBlock(
                  text: 'Jawaban tumbuh lengkap.',
                  sources: [source],
                ),
              ],
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('Jawaban tumbuh lengkap.'), findsOneWidget);
        expect(find.text('Bab I'), findsOneWidget);
        final complete = ChatAnswer(
          status: ChatAnswerStatus.answered,
          formatVersion: 2,
          blocks: [
            ChatAnswerBlock(text: 'Jawaban tumbuh lengkap.', sources: [source]),
          ],
        );
        vm.push(
          vm.current.copyWith(
            turns: [turn(1, answer: complete)],
            phase: ChatPhase.done,
            preview: null,
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('Jawaban tumbuh lengkap.'), findsOneWidget);
        expect(find.text('Lagi nulis…'), findsNothing);
        expect(find.text('Bab I'), findsOneWidget);
        vm.push(
          vm.current.copyWith(
            turns: [turn(1, phase: ChatPhase.cut)],
            phase: ChatPhase.cut,
            error: const AiException(AiError.invalidResponse),
            preview: (
              attempt: writing.attemptRef,
              blocks: [
                ChatAnswerBlock(text: 'Jawaban tumbuh lengkap.', sources: []),
              ],
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('Jawaban tumbuh lengkap.'), findsOneWidget);
        expect(find.text('Bab I'), findsNothing);
        expect(find.text('Coba lagi'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'new sent question jumps to latest once, then streaming stays put',
    (t) async {
      await open(
        t,
        size: const Size(390, 844),
        state: ChatState(
          book: book,
          loading: false,
          activeSession: session(1),
          turns: [for (var i = 1; i <= 30; i++) turn(i, answer: answer)],
        ),
      );
      await t.drag(find.byType(CustomScrollView), const Offset(0, 600));
      await t.pumpAndSettle();
      final scroll = t
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      final before = scroll.pixels;
      final sent = turn(31, phase: ChatPhase.waiting);
      vm.push(
        vm.current.copyWith(
          turns: [...vm.current.turns, sent],
          phase: ChatPhase.waiting,
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Pertanyaan 31'), findsOneWidget);
      expect(scroll.pixels, greaterThan(before));
      expect(scroll.extentAfter, closeTo(0, 1));
      final afterSend = scroll.pixels;
      vm.push(
        vm.current.copyWith(
          phase: ChatPhase.writing,
          preview: (
            attempt: sent.attemptRef,
            blocks: [
              ChatAnswerBlock(text: 'Jawaban panjang ' * 300, sources: []),
            ],
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(scroll.pixels, afterSend);
      expect(find.text('Ke terbaru'), findsOneWidget);
    },
  );

  testWidgets(
    'growth from bottom never follows, including chip and final drain',
    (t) async {
      final writing = turn(1, phase: ChatPhase.writing);
      final text = 'Paragraf panjang. ' * 200;
      await open(
        t,
        size: const Size(390, 844),
        state: ChatState(
          book: book,
          loading: false,
          activeSession: session(1),
          turns: [writing],
          phase: ChatPhase.writing,
        ),
      );
      final scroll = t
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      final before = scroll.pixels;
      vm.push(
        vm.current.copyWith(
          preview: (
            attempt: writing.attemptRef,
            blocks: [
              ChatAnswerBlock(text: text, sources: [source]),
            ],
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(scroll.pixels, before);
      await t.pumpAndSettle();
      expect(scroll.pixels, before);
      vm.push(
        vm.current.copyWith(
          phase: ChatPhase.done,
          preview: null,
          turns: [
            turn(
              1,
              answer: ChatAnswer(
                status: ChatAnswerStatus.answered,
                blocks: [
                  ChatAnswerBlock(text: '$text Akhir.', sources: [source]),
                ],
              ),
            ),
          ],
        ),
      );
      await t.pumpAndSettle();
      expect(scroll.pixels, before);
      await t.tap(find.text('Ke terbaru'));
      await t.pumpAndSettle();
      expect(scroll.pixels, greaterThan(before));
    },
  );

  testWidgets(
    'streaming growth and final citation keep scroll-up position stable',
    (t) async {
      final writing = turn(1, phase: ChatPhase.writing);
      final long = List.filled(100, 'Teks yang sedang tumbuh.').join('\n');
      await open(
        t,
        size: const Size(390, 844),
        state: ChatState(
          book: book,
          loading: false,
          activeSession: session(1),
          turns: [writing],
          phase: ChatPhase.writing,
          preview: (
            attempt: writing.attemptRef,
            blocks: [ChatAnswerBlock(text: long, sources: [])],
          ),
        ),
      );
      final scroll = t
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      await t.drag(find.byType(CustomScrollView), const Offset(0, 400));
      await t.pumpAndSettle();
      final away = scroll.offset;
      expect(find.text('Ke terbaru'), findsOneWidget);
      vm.push(
        vm.current.copyWith(
          preview: (
            attempt: writing.attemptRef,
            blocks: [
              ChatAnswerBlock(text: '$long\nTambahan', sources: [source]),
            ],
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(scroll.offset, closeTo(away, 1));
      vm.push(
        vm.current.copyWith(
          phase: ChatPhase.done,
          turns: [
            turn(
              1,
              answer: ChatAnswer(
                status: ChatAnswerStatus.answered,
                blocks: [
                  ChatAnswerBlock(text: '$long\nTambahan', sources: [source]),
                ],
              ),
            ),
          ],
          preview: null,
        ),
      );
      await t.pumpAndSettle();
      expect(scroll.offset, closeTo(away, 1));
      await t.tap(find.text('Ke terbaru'));
      await t.pumpAndSettle();
      expect(scroll.offset, greaterThan(away));
      expect(t.takeException(), isNull);
    },
  );

  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('global progress, Stop and explicit Continue in $theme', (
      t,
    ) async {
      final checkpoint = ChatExploration(
        book: book,
        sessionId: 1,
        turnId: 1,
        question: 'Pertanyaan 1',
        model: 'test',
        manifest: 'a' * 64,
        query: 'question',
        cursor: 8,
        total: 20,
        notes: [],
      ).encode();
      final partial = turn(1, answer: answer, exploration: checkpoint);
      await open(
        t,
        themeMode: theme,
        state: ChatState(
          book: book,
          loading: false,
          activeSession: session(1),
          turns: [partial],
          phase: ChatPhase.done,
        ),
      );
      expect(find.text('Lanjutkan'), findsOneWidget);
      expect(vm.continuations, 0);
      await t.tap(find.text('Lanjutkan'));
      await t.pump();
      expect(vm.continuations, 1);
      expect(find.text('Lanjutkan'), findsNothing);
      vm.push(
        vm.current.copyWith(
          explorationProgress: (completed: 8, total: 20),
          turns: [
            partial,
            turn(2, phase: ChatPhase.retrieving),
          ],
        ),
      );
      await t.pump();
      expect(find.text('Lagi meriksa isi buku… 8/20 potongan'), findsOneWidget);
      // A running continuation receives its own turn; prior answer remains visible.
      expect(find.text('Jawaban tervalidasi.'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(button('Hentikan jawaban'));
      await t.pumpAndSettle();
      expect(vm.stops, 1);
    });

    testWidgets('natural paragraphs and optional citations render in $theme', (
      tester,
    ) async {
      final natural = ChatAnswer(
        status: ChatAnswerStatus.partial,
        formatVersion: 2,
        blocks: [
          ChatAnswerBlock(text: 'Gagasan dalam buku.', sources: [source]),
          ChatAnswerBlock(
            text: 'Kalau diterapkan, saran gua begini.',
            sources: [source],
            kind: ChatAnswerKind.interpretation,
          ),
          ChatAnswerBlock(
            text: 'Ini pengetahuan tambahan.',
            sources: [],
            kind: ChatAnswerKind.external,
          ),
          ChatAnswerBlock(
            text: 'Bagian terakhir belum punya bukti.',
            sources: [],
            kind: ChatAnswerKind.conversation,
          ),
        ],
      );
      await open(
        tester,
        themeMode: theme,
        state: ChatState(
          book: book,
          loading: false,
          activeSession: session(1),
          turns: [turn(1, answer: natural)],
        ),
      );
      for (final block in natural.blocks) {
        expect(find.text(block.text), findsOneWidget);
      }
      expect(find.text('Bab I'), findsNWidgets(2));
      expect(
        find.text(
          'Sebagian pertanyaan belum punya bukti yang cukup di sumber ini.',
        ),
        findsNothing,
      );
      expect(vm.sends, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('index progress and Stop remain available in $theme', (
      tester,
    ) async {
      await open(
        tester,
        themeMode: theme,
        state: ChatState(
          book: book,
          loading: false,
          activeSession: session(1),
          turns: [turn(1, phase: ChatPhase.retrieving)],
          phase: ChatPhase.retrieving,
          indexProgress: (completed: 64, total: 100),
        ),
      );
      expect(find.text('Lagi nyiapin buku… 64/100 potongan'), findsOneWidget);
      expect(tester.takeException(), isNull);
      vm.push(vm.current.copyWith(phase: ChatPhase.slow));
      await tester.pump();
      expect(find.text('Lagi nyiapin buku… 64/100 potongan'), findsOneWidget);
      expect(find.text('Agak lama nih, masih diproses…'), findsNothing);
      vm.push(vm.current.copyWith(indexProgress: (completed: 80, total: 100)));
      await tester.pump();
      expect(find.text('Lagi nyiapin buku… 80/100 potongan'), findsOneWidget);
      vm.push(
        vm.current.copyWith(
          phase: ChatPhase.retrieving,
          indexProgress: (completed: 100, total: 100),
        ),
      );
      await tester.pump();
      expect(find.text('Lagi nyari sumber di buku…'), findsOneWidget);
      expect(vm.sends, 0);
      await tester.tap(button('Hentikan jawaban'));
      await tester.pumpAndSettle();
      expect(vm.stops, 1);
      expect(find.text('Jawaban dihentikan'), findsOneWidget);
    });
  }

  testWidgets('launch extra is applied once and mismatched book is ignored', (
    t,
  ) async {
    final context = ChatLaunchContext(
      book: book,
      returnPosition: (chapterId: 1, paragraphIndex: 0, paragraphOffset: 0),
    );
    await open(t, actualRouter: true, extra: context);
    expect(vm.launches, 1);
    vm.push(vm.current.copyWith(draft: 'same route'));
    await t.pumpAndSettle();
    expect(vm.launches, 1);
  });

  testWidgets('mismatched entry extra cannot launch another book', (t) async {
    final context = ChatLaunchContext(
      book: (bookId: 2, contentRevision: 1),
      returnPosition: (chapterId: 1, paragraphIndex: 0, paragraphOffset: 0),
    );
    await open(t, actualRouter: true, extra: context);
    expect(vm.launches, 0);
    expect(vm.sends, 0);
  });

  testWidgets('dark phone with large text keeps composer reachable', (t) async {
    await open(t, size: const Size(390, 844), themeMode: ThemeMode.dark);
    t.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(t.getSize(button('Kirim pertanyaan')), const Size(44, 44));
  });

  testWidgets('keyboard preserves offset until explicit latest action', (
    t,
  ) async {
    await open(
      t,
      size: const Size(390, 844),
      state: ChatState(
        book: book,
        loading: false,
        activeSession: session(1),
        turns: [for (var i = 1; i <= 20; i++) turn(i, answer: answer)],
      ),
    );
    final scroll = t
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    final before = scroll.pixels;
    t.view.viewInsets = const FakeViewPadding(bottom: 300);
    await t.pumpAndSettle();
    expect(scroll.pixels, before);
    await t.tap(find.text('Ke terbaru'));
    await t.pumpAndSettle();
    expect(
      t.getBottomLeft(find.text('Bab I').last).dy,
      lessThan(t.getTopLeft(find.byType(ChatComposer)).dy),
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('history initially opens newest without persisted pixels', (
    t,
  ) async {
    await open(
      t,
      state: ChatState(
        book: book,
        loading: false,
        activeSession: session(1),
        turns: [for (var i = 1; i <= 100; i++) turn(i, answer: answer)],
      ),
    );
    expect(find.text('Pertanyaan 100'), findsOneWidget);
    expect(find.text('Pertanyaan 1'), findsNothing);
  });

  test('chat errors map safe recovery copy and local date groups', () {
    for (final error in [
      const AiException(AiError.noApiKey),
      const AiException(AiError.network),
      const AiException(AiError.timeout),
      const AiException(AiError.invalidResponse),
      for (final status in [401, 402, 403, 429, 500])
        AiException(AiError.http, status: status, detail: 'PRIVATE'),
    ]) {
      expect(error.chatMessage, isNotEmpty);
      expect(error.chatMessage, isNot(contains('PRIVATE')));
    }
    expect(const AiException(AiError.http, status: 402).needsSettings, isTrue);
    expect(const AiException(AiError.http, status: 429).needsSettings, isFalse);
    expect(chatTimeGroup(now, now), 'Hari ini');
    expect(
      chatTimeGroup(now.subtract(const Duration(days: 1)), now),
      'Kemarin',
    );
    expect(
      chatTimeGroup(now.subtract(const Duration(days: 3)), now),
      'Sebelumnya',
    );
  });

  testWidgets('selected quote can be removed without creating a session', (
    t,
  ) async {
    await open(
      t,
      state: ChatState(
        book: book,
        loading: false,
        selectedQuote: ChatQuote(anchors: source.anchors),
      ),
    );
    expect(find.text('Bukti'), findsOneWidget);
    await t.tap(button('Lepas kutipan'));
    await t.pump();
    expect(find.text('Bukti'), findsNothing);
    expect(vm.creates, 0);
    expect(vm.sends, 0);
  });

  for (final status in [ChatAnswerStatus.partial, ChatAnswerStatus.notFound]) {
    testWidgets('${status.name} shows fixed limitation note', (t) async {
      final response = ChatAnswer(
        status: status,
        blocks: status == ChatAnswerStatus.notFound ? [] : answer.blocks,
      );
      await open(
        t,
        state: ChatState(
          book: book,
          loading: false,
          activeSession: session(1),
          turns: [turn(1, answer: response)],
        ),
      );
      expect(find.text(response.note), findsOneWidget);
      expect(find.textContaining('secret raw'), findsNothing);
    });
  }

  testWidgets('empty composer, examples and growing input never auto send', (
    t,
  ) async {
    await open(t);
    expect(vm.sends, 0);
    await t.enterText(find.byType(TextField), '   ');
    await t.tap(button('Kirim pertanyaan'));
    expect(vm.sends, 0);
    await t.tap(find.text('Apa gagasan utama buku ini?'));
    await t.pump();
    expect(vm.sends, 0);
    expect(find.text('Apa gagasan utama buku ini?'), findsNWidgets(2));
    await t.enterText(find.byType(TextField), 'a\nb\nc\nd\ne\nf\ng');
    await t.pump();
    final field = t.widget<TextField>(find.byType(TextField));
    expect(field.minLines, 1);
    expect(field.maxLines, 5);
    expect(t.getSize(button('Kirim pertanyaan')), const Size(44, 44));
    await t.tap(button('Kirim pertanyaan'));
    await t.pump();
    expect(vm.sends, 1);
    await t.tap(button('Hentikan jawaban'));
    await t.pump();
    expect(vm.stops, 1);
  });

  testWidgets(
    'validated blocks and source labels render, raw partial never renders',
    (t) async {
      await open(
        t,
        state: ChatState(
          book: book,
          loading: false,
          activeSession: session(1),
          turns: [
            turn(1, answer: answer),
            turn(2, phase: ChatPhase.cut),
          ],
          phase: ChatPhase.cut,
        ),
      );
      expect(find.text('Jawaban tervalidasi.'), findsOneWidget);
      expect(find.text('Bab I'), findsOneWidget);
      expect(find.textContaining('secret raw'), findsNothing);
      expect(find.text('Jawabannya kepotong'), findsOneWidget);
      await t.tap(find.text('Coba lagi'));
      expect(vm.sends, 1);
    },
  );

  testWidgets('no key settings action waits stop and preserves draft', (
    t,
  ) async {
    await open(
      t,
      state: ChatState(
        book: book,
        loading: false,
        draft: 'Draft utuh',
        error: const AiException(AiError.noApiKey, detail: 'SECRET'),
      ),
    );
    expect(find.textContaining('SECRET'), findsNothing);
    vm.stopGate = Completer<void>();
    await t.tap(find.text('Buka Pengaturan'));
    await t.pump();
    expect(find.text('Settings'), findsNothing);
    vm.stopGate!.complete();
    await t.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    router.pop();
    await t.pumpAndSettle();
    expect(find.text('Draft utuh'), findsOneWidget);
    expect(vm.sends, 0);
  });

  testWidgets(
    'rename validates title and cancel/delete affects active session only',
    (t) async {
      await open(
        t,
        state: ChatState(book: book, loading: false, activeSession: session(2)),
      );
      await t.tap(button('Menu sesi'));
      await t.pumpAndSettle();
      await t.tap(find.text('Ubah judul'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, '   ');
      await t.pump();
      expect(find.text('Judul belum diisi'), findsOneWidget);
      await t.enterText(find.byType(TextField).last, 'x' * 121);
      await t.pump();
      expect(find.text('Judul maksimal 120 karakter'), findsOneWidget);
      await t.enterText(find.byType(TextField).last, '  Judul baru  ');
      await t.pump();
      await t.tap(find.text('Simpan judul'));
      await t.pumpAndSettle();
      expect(vm.renamed, ['Judul baru']);
      await t.tap(button('Menu sesi'));
      await t.pumpAndSettle();
      await t.tap(find.text('Hapus obrolan ini'));
      await t.pumpAndSettle();
      await t.tap(find.text('Batal'));
      await t.pumpAndSettle();
      expect(vm.deleted, isEmpty);
      await t.tap(button('Menu sesi'));
      await t.pumpAndSettle();
      await t.tap(find.text('Hapus obrolan ini'));
      await t.pumpAndSettle();
      await t.tap(find.text('Hapus'));
      await t.pumpAndSettle();
      expect(vm.deleted, [2]);
    },
  );

  testWidgets(
    'history filters another book, selects exact session and creates unsaved draft',
    (t) async {
      await open(t, sessions: [session(1), session(9, bookId: 2), session(3)]);
      vm.stopGate = Completer<void>();
      await t.tap(button('Riwayat obrolan'));
      await t.pump();
      expect(find.text('Obrolan buku ini'), findsNothing);
      vm.stopGate!.complete();
      await t.pumpAndSettle();
      expect(find.text('Topik 9'), findsNothing);
      await t.tap(find.text('Topik 3'));
      await t.pumpAndSettle();
      expect(vm.opened, [3]);
      await t.tap(button('Riwayat obrolan'));
      await t.pumpAndSettle();
      await t.tap(find.text('Obrolan baru').last);
      await t.pumpAndSettle();
      expect(vm.creates, 1);
      expect(vm.sends, 0);
    },
  );

  testWidgets('archived sessions are read only with new chat recovery', (
    t,
  ) async {
    await open(
      t,
      state: ChatState(
        book: book,
        loading: false,
        activeSession: session(1, revision: 2),
      ),
    );
    expect(find.byType(ChatComposer), findsNothing);
    await t.tap(find.text('Obrolan baru').last);
    await t.pumpAndSettle();
    expect(vm.creates, 1);
    expect(find.byType(ChatComposer), findsOneWidget);
  });

  testWidgets('phone composer and keyboard keep send reachable', (t) async {
    await open(t, size: const Size(390, 844));
    t.view.viewInsets = const FakeViewPadding(bottom: 300);
    await t.enterText(find.byType(TextField), 'a\nb\nc\nd\ne\nf');
    await t.pumpAndSettle();
    expect(t.getBottomLeft(button('Kirim pertanyaan')).dy, lessThan(544));
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'long answer can scroll up slowly from latest without snapping back',
    (t) async {
      final longAnswer = ChatAnswer(
        status: ChatAnswerStatus.answered,
        blocks: [
          ChatAnswerBlock(
            text: List.filled(
              100,
              'Jawaban panjang yang bisa dibaca dengan menggulir.',
            ).join('\n'),
            sources: [source],
          ),
        ],
      );
      await open(
        t,
        size: const Size(390, 844),
        state: ChatState(
          book: book,
          loading: false,
          activeSession: session(1),
          turns: [turn(1, answer: longAnswer)],
        ),
      );
      final scroll = t
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      final bottom = scroll.offset;
      final gesture = await t.startGesture(
        t.getCenter(find.byType(CustomScrollView)),
      );
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(0, 20));
        if (i == 2) vm.push(vm.current.copyWith(phase: ChatPhase.waiting));
        await t.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await t.pumpAndSettle();
      expect(scroll.offset, lessThan(bottom - 150));
      expect(find.text('Ke terbaru'), findsOneWidget);
      final away = scroll.offset;
      vm.push(vm.current.copyWith(turns: [...vm.current.turns]));
      await t.pumpAndSettle();
      expect(scroll.offset, closeTo(away, 1));
    },
  );

  testWidgets(
    'long history is lazy and respects scroll away and stable anchor',
    (t) async {
      await open(
        t,
        state: ChatState(
          book: book,
          loading: false,
          activeSession: session(1),
          turns: [for (var i = 1; i <= 1000; i++) turn(i, answer: answer)],
          scrollAnchor: (turnId: 50, blockIndex: 0, alignment: 0),
        ),
      );
      expect(find.text('Pertanyaan 50'), findsOneWidget);
      expect(find.text('Pertanyaan 1'), findsNothing);
      await t.drag(find.byType(CustomScrollView), const Offset(0, 300));
      await t.pumpAndSettle();
      expect(find.text('Ke terbaru'), findsOneWidget);
      final before = vm.current.scrollAnchor;
      vm.push(vm.current.copyWith(turns: [...vm.current.turns, turn(1001)]));
      await t.pumpAndSettle();
      expect(find.text('Ke terbaru'), findsOneWidget);
      expect(vm.current.scrollAnchor, before);
      await t.tap(find.text('Ke terbaru'));
      await t.pumpAndSettle();
      expect(find.text('Pertanyaan 1001'), findsOneWidget);
    },
  );

  testWidgets('production invalid routes reject non numeric ids safely', (
    t,
  ) async {
    await open(t, path: '/reader/nope/chat/sessions', actualRouter: true);
    expect(find.text('Alamat obrolan gak valid. Kembali'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('production route back awaits stop before disposing chat', (
    t,
  ) async {
    await open(t, path: '/reader/bad/chat', actualRouter: true);
    unawaited(router.push(Routes.chat(1)));
    await t.pumpAndSettle();
    vm.stopGate = Completer<void>();
    router.pop();
    await t.pump();
    expect(find.byType(ChatView), findsOneWidget);
    vm.stopGate!.complete();
    await t.pumpAndSettle();
    expect(find.text('Alamat obrolan gak valid. Kembali'), findsOneWidget);
    expect(vm.stops, 1);
  });
}
