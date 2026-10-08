import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/domain/breakdown_prompt.dart';
import 'package:luma/domain/models/ai_reply.dart';
import 'package:luma/domain/models/breakdown.dart';
import 'package:luma/routing/router.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/core/widgets/buttons.dart';
import 'package:luma/ui/features/breakdown/views/breakdown_view.dart';
import 'package:luma/ui/features/reader/view_models/breakdown_view_model.dart';
import 'package:luma/ui/features/reader/view_models/reader_view_model.dart';
import 'package:luma/domain/ai_prompt.dart';

import '../../../fakes.dart';

const g = (chapterId: 10, groupIndex: 0);

BreakdownInput input(List<String> translations) => BreakdownInput(
  book: (title: 'Enchiridion', author: 'Epictetus', chapter: 'XXIV'),
  chapters: const ['I', 'XVII', 'XXIV'],
  chapter: 3,
  original: [for (final t in translations) 'EN $t'],
  translations: translations,
  meaning: 'Makna cepat.',
);

/// One paragraph, four sentences (K1..K4).
final onePara = input(['Satu dua. Tiga empat. Lima enam. Tujuh delapan.']);

/// Three paragraphs: K1–K2, K3, K4.
final threePara = input(['Satu. Dua.', 'Tiga.', 'Empat.']);

BreakdownSection section(int from, int to, String name) => BreakdownSection(
  from: from,
  to: to,
  title: 'Judul $name',
  meaning: 'Maksud $name.',
  logic: 'Logika $name.',
);

BreakdownState done(Breakdown b, {BreakdownInput? from, bool cached = true}) =>
    BreakdownState(
      phase: BreakdownPhase.done,
      input: from ?? onePara,
      draft: b,
      cached: cached,
    );

final one = Breakdown(sections: [section(1, 4, 'satu')]);
final two = Breakdown(sections: [section(1, 2, 'satu'), section(3, 4, 'dua')]);
final four = Breakdown(
  sections: [for (var i = 1; i <= 4; i++) section(i, i, '$i')],
);

/// Where each Nyambung ke card leads (by chapter, null = next group).
var peeks = <int?, BreakdownPeek?>{};

/// Artiin in the peek sheet: tests push the stream states.
class FakeArtiin extends GroupAiStream {
  FakeArtiin(super.group);

  static final live = <GroupRef, FakeArtiin>{};

  @override
  AiStream build() {
    live[this.group] = this;
    return const AiStream();
  }

  void push(AiStream next) => state = next;
}

void main() {
  late bool? popped;

  setUp(() {
    FakeBreakdown.reset();
    FakeArtiin.live.clear();
    peeks = {};
    popped = null;
  });

  Finder panel() => find.byWidgetPredicate(
    (w) =>
        w is Semantics &&
        (w.properties.label?.startsWith('Teks') ?? false) &&
        w.properties.label != 'Teks yang dibedah',
  );
  Finder inlinePanel() => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == 'Teks yang dibedah',
  );
  AppButton button(WidgetTester tester, String label) => tester.widget(
    find.ancestor(of: find.text(label), matching: find.byType(AppButton)),
  );

  /// Opens the screen from a page underneath (like the Artinya sheet), so
  /// back and "Balik baca" have somewhere to go.
  Future<void> open(
    WidgetTester tester,
    BreakdownState state, {
    bool reduce = false,
    bool voiceOver = false,
    Size size = const Size(900, 1400),
  }) async {
    FakeBreakdown.initial = state;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => popped = await context.push<bool>(
                  Routes.breakdown(1, g.chapterId, g.groupIndex),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/reader/:bookId/breakdown/:chapterId/:groupIndex',
          builder: (_, state) => BreakdownView(
            bookId: int.parse(state.pathParameters['bookId']!),
            group: (
              chapterId: int.parse(state.pathParameters['chapterId']!),
              groupIndex: int.parse(state.pathParameters['groupIndex']!),
            ),
          ),
        ),
        GoRoute(
          path: Routes.settings,
          builder: (_, _) => const Scaffold(body: Text('Pengaturan')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          breakdownStreamProvider.overrideWith2(FakeBreakdown.new),
          breakdownPeekProvider.overrideWith(
            (ref, key) async => peeks[key.chapter],
          ),
          groupAiStreamProvider.overrideWith2(FakeArtiin.new),
          settingsRepositoryProvider.overrideWithValue(FakeSettings()),
        ],
        child: MaterialApp.router(
          theme: stabiloTheme(Brightness.light),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reduce,
              accessibleNavigation: voiceOver,
            ),
            child: child!,
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // Placeholders shimmer forever: no pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  FakeBreakdown fake() => FakeBreakdown.live[g]!;

  group('layout follows the section count', () {
    testWidgets('1 section: no numbers or titles, panel scrolls along, '
        'original text below', (tester) async {
      await open(tester, done(one));
      expect(find.text('Udah dibedah nih'), findsOneWidget);
      expect(find.text('Enchiridion · XXIV · 1 gagasan'), findsOneWidget);
      expect(inlinePanel(), findsOneWidget);
      expect(panel(), findsNothing);
      expect(find.text('Judul satu'), findsNothing);
      expect(find.text('1'), findsNothing);
      expect(find.text('MAKSUDNYA'), findsOneWidget);
      expect(find.text('Maksud satu.'), findsOneWidget);
      expect(find.text('LOGIKANYA'), findsOneWidget);
      expect(find.textContaining('EN Satu dua.'), findsOneWidget);
      // Panel and explanation share one scroll view.
      final scroll = find.ancestor(
        of: inlinePanel(),
        matching: find.byType(SingleChildScrollView),
      );
      expect(
        find.descendant(of: scroll, matching: find.text('Maksud satu.')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('2 sections: numbers in the text + titles, pinned panel as '
        'tall as its text', (tester) async {
      await open(tester, done(two));
      expect(find.text('Enchiridion · XXIV · 2 bagian'), findsOneWidget);
      expect(
        find.descendant(of: panel(), matching: find.text('1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel(), matching: find.text('2')),
        findsOneWidget,
      );
      expect(find.text('Judul satu'), findsOneWidget);
      expect(find.text('Judul dua'), findsOneWidget);
      expect(tester.getSize(panel()).height, lessThan(1400 * 0.4));
      // Pinned: the panel is not inside the explanation scroll.
      expect(
        find.ancestor(
          of: find.text('Maksud satu.'),
          matching: find.byWidgetPredicate(
            (w) => w is SingleChildScrollView && w.child is Padding,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('4 sections with long text: panel caps at 40% and scrolls', (
      tester,
    ) async {
      final long = input([
        for (var i = 0; i < 4; i++) 'Kalimat $i ${'kata ' * 40}ujung.',
      ]);
      await open(tester, done(four, from: long));
      expect(tester.getSize(panel()).height, 1400 * 0.4);
      final inner = find.descendant(
        of: panel(),
        matching: find.byType(Scrollable),
      );
      expect(
        tester.state<ScrollableState>(inner).position.maxScrollExtent,
        greaterThan(0),
      );
      for (var i = 1; i <= 4; i++) {
        expect(find.text('Judul $i'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('3 paragraphs: ¶n in the margin, crossing sections get ¶a–b', (
      tester,
    ) async {
      await open(
        tester,
        done(
          Breakdown(sections: [section(1, 2, 'satu'), section(3, 4, 'dua')]),
          from: threePara,
        ),
      );
      for (final p in ['¶1', '¶2', '¶3']) {
        expect(find.text(p), findsOneWidget);
      }
      expect(find.text('¶2–3'), findsOneWidget); // K3 in ¶2, K4 in ¶3
      // Paragraphs stay apart: ¶2 starts below ¶1's text.
      expect(
        tester.getTopLeft(find.text('¶2')).dy,
        greaterThan(tester.getTopLeft(find.text('¶1')).dy),
      );
    });
  });

  testWidgets('optional blocks only show with content', (tester) async {
    await open(
      tester,
      done(
        Breakdown(
          sections: two.sections,
          terms: const [
            BreakdownTerm(
              label: 'Dogma',
              exact: 'Lima',
              explanation: 'Penilaian kita.',
              sentence: 3,
            ),
            BreakdownTerm(label: 'Stoa', explanation: 'Serambi.'),
          ],
          links: const [
            BreakdownLink(chapter: 2, title: 'Aktor', why: 'peran.'),
            BreakdownLink(title: 'Terusannya', why: 'lanjut.'),
          ],
          practice: 'Pisahin kejadian sama pendapat lo.',
        ),
      ),
    );
    final scroll = find.byType(Scrollable).last;
    Future<void> see(Finder f) =>
        tester.scrollUntilVisible(f, 200, scrollable: scroll);
    await see(find.text('TOKOH & ISTILAH'));
    expect(find.text('Dogma · bagian 2'), findsOneWidget);
    expect(find.text('Stoa'), findsOneWidget); // no sentence: no section
    await see(find.text('NYAMBUNG KE'));
    expect(find.text('XVII'), findsOneWidget);
    expect(find.text('Aktor: peran.'), findsOneWidget);
    expect(find.text('LANJUTAN XXIV'), findsOneWidget);
    await see(find.text('Pisahin kejadian sama pendapat lo.'));
    expect(find.text('PRAKTEKINNYA GINI'), findsOneWidget);
  });

  testWidgets('no optional content: no empty headings', (tester) async {
    await open(tester, done(two));
    expect(find.text('TOKOH & ISTILAH'), findsNothing);
    expect(find.text('NYAMBUNG KE'), findsNothing);
    expect(find.text('PRAKTEKINNYA GINI'), findsNothing);
  });

  group('states', () {
    testWidgets('waiting: translation already up, placeholders, status', (
      tester,
    ) async {
      await open(tester, BreakdownState(input: onePara));
      expect(find.text('Lagi ngebedah...'), findsOneWidget);
      expect(find.text('Enchiridion · XXIV'), findsOneWidget);
      expect(find.textContaining('Satu dua.'), findsOneWidget);
      expect(find.text('Lagi mikir'), findsOneWidget);
      expect(find.text('Salin'), findsNothing);
      expect(find.text('MAKSUDNYA'), findsNothing);
      expect(
        find.bySemanticsLabel('Batalin, balik ke Artinya'),
        findsOneWidget,
      );
      expect(button(tester, 'Balik baca').onPressed, isNotNull);
    });

    testWidgets('writing: paced, numbers once two sections are in, then '
        'done turns on Salin', (tester) async {
      await open(tester, BreakdownState(input: onePara));
      fake().push(
        BreakdownState(
          phase: BreakdownPhase.writing,
          input: onePara,
          draft: Breakdown(sections: [section(1, 2, 'satu')]),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Lagi nulis'), findsOneWidget);
      // Paced: the explanation isn't all out yet.
      expect(find.text('Logika satu.'), findsNothing);
      expect(
        find.descendant(of: panel(), matching: find.text('1')),
        findsNothing,
      );

      fake().push(
        BreakdownState(phase: BreakdownPhase.done, input: onePara, draft: two),
      );
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Logika dua.'), findsOneWidget);
      expect(
        find.descendant(of: panel(), matching: find.text('2')),
        findsOneWidget,
      );
      expect(find.text('Udah dibedah nih'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(button(tester, 'Salin').onPressed, isNotNull);
      expect(find.bySemanticsLabel('Balik ke Artinya'), findsOneWidget);
    });

    testWidgets('slow: card on top; Coba lagi starts over, Batal goes back', (
      tester,
    ) async {
      await open(
        tester,
        BreakdownState(phase: BreakdownPhase.slow, input: onePara),
      );
      expect(find.text('Agak lama nih...'), findsOneWidget);
      expect(find.text('Lagi mikir'), findsOneWidget);
      await tester.tap(find.text('Coba lagi'));
      await tester.pump();
      expect(FakeBreakdown.builds, 2);

      fake().push(BreakdownState(phase: BreakdownPhase.slow, input: onePara));
      await tester.pump();
      await tester.tap(find.text('Batal'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('open'), findsOneWidget);
      expect(popped, isNull); // back to Artinya, not to the page
    });

    testWidgets('cut: whole sections kept, banner retries, Salin off', (
      tester,
    ) async {
      await open(tester, BreakdownState(input: onePara));
      fake().push(
        BreakdownState(
          phase: BreakdownPhase.cut,
          input: onePara,
          draft: Breakdown(
            sections: [
              section(1, 1, 'satu'),
              section(2, 2, 'dua'),
              const BreakdownSection(from: 3, to: 3, title: 'Kepo'),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Kepotong di tengah'), findsOneWidget);
      expect(find.text('Enchiridion · XXIV · 2 bagian masuk'), findsOneWidget);
      expect(find.text('Judul dua'), findsOneWidget);
      expect(find.text('Kepo'), findsNothing);
      expect(
        find.descendant(of: panel(), matching: find.text('3')),
        findsNothing,
      );
      expect(find.textContaining('Bagian 1–2 tetep di sini.'), findsOneWidget);
      expect(button(tester, 'Salin').onPressed, isNull);
      await tester.tap(find.text('Coba lagi dari awal'));
      await tester.pump();
      expect(FakeBreakdown.builds, 2);
    });

    final errors = {
      const AiException(AiError.timeout): (
        'Yah, gagal ngebedah',
        'timeout · 30 detik',
        'Coba lagi',
      ),
      const AiException(AiError.network): (
        'Lagi offline nih',
        'offline',
        'Coba lagi',
      ),
      const AiException(AiError.http, status: 401): (
        'API key-nya ditolak',
        '401 · key ditolak',
        'Buka Pengaturan',
      ),
      const AiException(AiError.http, status: 402): (
        'Saldo OpenRouter abis',
        '402 · saldo abis',
        'Coba lagi',
      ),
      const AiException(AiError.invalidResponse): (
        'Jawabannya berantakan',
        'format gak valid',
        'Coba lagi',
      ),
    };
    for (final MapEntry(key: error, value: (title, code, action))
        in errors.entries) {
      testWidgets('error ${error.error.name} ${error.status ?? ''}', (
        tester,
      ) async {
        await open(
          tester,
          BreakdownState(
            phase: BreakdownPhase.failed,
            input: onePara,
            error: error,
          ),
        );
        expect(find.text('Bedahin'), findsOneWidget);
        expect(find.textContaining('Satu dua.'), findsOneWidget); // panel
        expect(find.text(title), findsOneWidget);
        expect(find.text(code), findsOneWidget);
        expect(button(tester, action).onPressed, isNotNull);
        expect(button(tester, 'Balik baca').onPressed, isNotNull);
        await tester.tap(find.text(action));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        if (action == 'Coba lagi') {
          expect(FakeBreakdown.builds, 2);
        } else {
          expect(find.text('Pengaturan'), findsOneWidget);
        }
      });
    }

    testWidgets('no API key: asks for one; back from Settings retries', (
      tester,
    ) async {
      await open(
        tester,
        const BreakdownState(
          phase: BreakdownPhase.failed,
          error: AiException(AiError.noApiKey),
        ),
      );
      expect(find.text('Isi API key dulu yuk'), findsOneWidget);
      expect(find.textContaining('openrouter.ai/keys'), findsOneWidget);
      await tester.tap(find.text('Buka Pengaturan'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Pengaturan'), findsOneWidget);
      expect(FakeBreakdown.builds, 1);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(FakeBreakdown.builds, 2);
    });
  });

  testWidgets('copy: plain text in the board format, toast, "Disalin"', (
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
    await open(
      tester,
      done(
        Breakdown(
          sections: two.sections,
          terms: const [BreakdownTerm(label: 'Stoa', explanation: 'Serambi.')],
          links: const [BreakdownLink(chapter: 2, title: 'A', why: 'b')],
          practice: 'Lakuin ini.',
        ),
      ),
    );
    await tester.tap(find.text('Salin'));
    await tester.pump();
    await tester.pump();
    expect(
      copied,
      'Enchiridion · XXIV (dibedah di Luma)\n\n'
      '1. Judul satu\nMaksudnya: Maksud satu.\nLogikanya: Logika satu.\n\n'
      '2. Judul dua\nMaksudnya: Maksud dua.\nLogikanya: Logika dua.\n\n'
      'Tokoh & istilah\n- Stoa: Serambi.\n\n'
      'Praktekinnya gini\nLakuin ini.',
    );
    expect(find.text('Disalin'), findsOneWidget);
    expect(find.text('Udah disalin, tinggal paste'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  test('copy of a single section has no number or title', () {
    expect(
      breakdownCopy(onePara, one),
      'Enchiridion · XXIV (dibedah di Luma)\n\n'
      'Maksudnya: Maksud satu.\nLogikanya: Logika satu.',
    );
  });

  testWidgets('"Balik baca" pops with true, back pops without', (tester) async {
    await open(tester, done(two));
    await tester.tap(find.text('Balik baca'));
    await tester.pumpAndSettle();
    expect(popped, isTrue);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Balik ke Artinya'));
    await tester.pumpAndSettle();
    expect(popped, isNull);
  });

  testWidgets('buttons hide on scroll down, come back on scroll up', (
    tester,
  ) async {
    await open(tester, done(four), size: const Size(900, 900));
    final scroll = find.byType(Scrollable).last;
    final before = tester.getTopLeft(find.text('Balik baca')).dy;
    await tester.drag(scroll, const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Balik baca')).dy, greaterThan(before));
    await tester.drag(scroll, const Offset(0, 30));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Balik baca')).dy, before);
  });

  testWidgets('VoiceOver: buttons never hide; headings per section', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await open(tester, done(four), voiceOver: true, size: const Size(900, 900));
    expect(
      find.bySemanticsLabel(
        'Bedahin, Enchiridion XXIV, 4 bagian, udah lengkap',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Bagian 1 dari 4, Judul 1'), findsOneWidget);
    final before = tester.getTopLeft(find.text('Balik baca')).dy;
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Balik baca')).dy, before);
    handle.dispose();
  });

  group('sync (#64)', () {
    final four = input(['Satu ini. Dua ini. Tiga ini. Empat ini.']);
    BreakdownSection long(int k) => BreakdownSection(
      from: k,
      to: k,
      title: 'Judul $k',
      meaning: 'Maksud $k ${'kata ' * 60}ujung.',
      logic: 'Logika $k ${'kata ' * 60}ujung.',
    );
    Breakdown sections(int n, {bool extras = false}) => Breakdown(
      sections: [for (var k = 1; k <= n; k++) long(k)],
      terms: extras
          ? const [
              BreakdownTerm(
                label: 'Tiga',
                exact: 'tiga',
                explanation: 'Angka.',
                sentence: 3,
              ),
            ]
          : const [],
      practice: extras ? 'Lakuin ini.' : null,
    );

    /// Text marked in the panel (section or term highlight).
    List<String> marked(WidgetTester tester) => [
      for (final rt in tester.widgetList<RichText>(
        find.descendant(of: panel(), matching: find.byType(RichText)),
      ))
        ...() {
          final out = <String>[];
          rt.text.visitChildren((span) {
            if (span is TextSpan &&
                span.text != null &&
                span.style?.backgroundColor != null) {
              out.add(span.text!);
            }
            return true;
          });
          return out;
        }(),
    ];
    Finder explanation() => find
        .ancestor(
          of: find.text('MAKSUDNYA').first,
          matching: find.byType(Scrollable),
        )
        .first;
    Finder chips() => find.byWidgetPredicate(
      (w) => w is ListView && w.scrollDirection == Axis.horizontal,
    );
    Finder chip(String label) =>
        find.descendant(of: chips(), matching: find.text(label));
    double explanationPixels(WidgetTester tester) =>
        tester.state<ScrollableState>(explanation()).position.pixels;

    testWidgets('first section highlighted from the start (cached)', (
      tester,
    ) async {
      await open(tester, done(sections(4), from: four));
      expect(marked(tester), ['Satu ini.']);
    });

    testWidgets('scrolling moves the highlight; back up returns it', (
      tester,
    ) async {
      await open(tester, done(sections(4), from: four));
      final seen = <String>{};
      for (var i = 0; i < 40; i++) {
        await tester.drag(explanation(), const Offset(0, -60));
        await tester.pump();
        seen.addAll(marked(tester));
      }
      expect(seen, containsAll(['Dua ini.', 'Tiga ini.', 'Empat ini.']));
      expect(marked(tester), ['Empat ini.']); // the end: last section
      await tester.drag(explanation(), const Offset(0, 6000));
      await tester.pumpAndSettle();
      expect(marked(tester), ['Satu ini.']);
    });

    testWidgets('tap a number in the text: the explanation jumps there', (
      tester,
    ) async {
      await open(tester, done(sections(4), from: four));
      await tester.tap(find.descendant(of: panel(), matching: find.text('3')));
      await tester.pumpAndSettle();
      expect(marked(tester), ['Tiga ini.']);
      final top = tester.getTopLeft(explanation()).dy;
      expect(
        tester.getTopLeft(find.text('Judul 3')).dy - top,
        inInclusiveRange(0, 40),
      );
    });

    testWidgets('chips only with 3+ sections; a chip jumps and turns ink', (
      tester,
    ) async {
      await open(tester, done(sections(2), from: four));
      expect(chips(), findsNothing);
      expect(marked(tester), ['Satu ini.']); // 2 sections still sync

      await open(tester, done(sections(4, extras: true), from: four));
      for (final l in ['1', '2', '3', '4', 'Istilah', 'Praktek']) {
        expect(chip(l), findsOneWidget);
      }
      await tester.tap(chip('2'));
      await tester.pumpAndSettle();
      expect(marked(tester), ['Dua ini.']);
      final on = tester.widget<Text>(chip('2')).style!.color;
      expect(on, tester.element(chip('2')).stabilo.canvas);
      expect(explanationPixels(tester), greaterThan(0));
    });

    testWidgets('past the last section the panel folds; tap opens it', (
      tester,
    ) async {
      await open(tester, done(sections(4, extras: true), from: four));
      await tester.tap(chip('Istilah'));
      await tester.pumpAndSettle();
      expect(panel(), findsNothing);
      expect(find.text('Teks terjemahan · 4 bagian'), findsOneWidget);
      await tester.tap(find.text('Teks terjemahan · 4 bagian'));
      await tester.pumpAndSettle();
      expect(panel(), findsOneWidget);
      // Back to a section: folding works again later.
      await tester.tap(chip('1'));
      await tester.pumpAndSettle();
      await tester.tap(chip('Praktek'));
      await tester.pumpAndSettle();
      expect(panel(), findsNothing);
    });

    testWidgets('tap the box: folds anywhere, stays folded while scrolling', (
      tester,
    ) async {
      await open(tester, done(sections(2), from: four));
      await tester.tap(find.textContaining('Dua ini.'));
      await tester.pumpAndSettle();
      expect(panel(), findsNothing);
      expect(find.text('Teks terjemahan · 2 bagian'), findsOneWidget);
      await tester.drag(explanation(), const Offset(0, -200));
      await tester.pumpAndSettle();
      await tester.drag(explanation(), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(panel(), findsNothing);
      await tester.tap(find.text('Teks terjemahan · 2 bagian'));
      await tester.pumpAndSettle();
      expect(panel(), findsOneWidget);
    });

    testWidgets('chevron folds; a number still jumps; a chip opens it', (
      tester,
    ) async {
      await open(tester, done(sections(4), from: four));
      await tester.tap(find.descendant(of: panel(), matching: find.text('3')));
      await tester.pumpAndSettle();
      expect(panel(), findsOneWidget); // the number jumped, didn't fold
      expect(marked(tester), ['Tiga ini.']);

      await tester.tap(find.bySemanticsLabel('Lipet teks terjemahan'));
      await tester.pumpAndSettle();
      expect(panel(), findsNothing);
      await tester.tap(chip('2'));
      await tester.pumpAndSettle();
      expect(panel(), findsOneWidget);
      expect(marked(tester), ['Dua ini.']);
    });

    testWidgets('no manual fold while writing', (tester) async {
      await open(tester, BreakdownState(input: four), reduce: true);
      fake().push(
        BreakdownState(
          phase: BreakdownPhase.writing,
          input: four,
          draft: Breakdown(sections: [long(1), long(2), long(3)]),
        ),
      );
      await tester.pump();
      expect(find.bySemanticsLabel('Lipet teks terjemahan'), findsNothing);
      await tester.tap(find.textContaining('Satu ini.'));
      await tester.pump();
      expect(panel(), findsOneWidget);
    });

    testWidgets('2 sections never fold', (tester) async {
      await open(tester, done(sections(2, extras: true), from: four));
      await tester.drag(explanation(), const Offset(0, -6000));
      await tester.pumpAndSettle();
      expect(panel(), findsOneWidget);
    });

    testWidgets('tap a term: its exact word is marked, the panel opens', (
      tester,
    ) async {
      await open(tester, done(sections(4, extras: true), from: four));
      await tester.tap(chip('Istilah'));
      await tester.pumpAndSettle();
      expect(panel(), findsNothing);
      await tester.tap(find.text('Angka.'));
      await tester.pumpAndSettle();
      expect(panel(), findsOneWidget);
      expect(marked(tester), ['Tiga']); // case kept from the text
      // A finger scroll clears it.
      await tester.drag(explanation(), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(marked(tester), isNot(contains('Tiga')));
    });

    testWidgets('streaming: the section being written is marked, no chips', (
      tester,
    ) async {
      await open(tester, BreakdownState(input: four), reduce: true);
      fake().push(
        BreakdownState(
          phase: BreakdownPhase.writing,
          input: four,
          draft: Breakdown(
            sections: [
              long(1),
              long(2),
              const BreakdownSection(from: 3, to: 4),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(marked(tester), ['Dua ini.']); // last whole one, reduce motion
      expect(chips(), findsNothing);
    });

    testWidgets('1 section: no highlight, chips or folding', (tester) async {
      await open(tester, done(sections(1, extras: true), from: four));
      expect(chips(), findsNothing);
      expect(find.byType(AnimatedSize), findsNothing);
      for (final rt in tester.widgetList<RichText>(
        find.descendant(of: inlinePanel(), matching: find.byType(RichText)),
      )) {
        rt.text.visitChildren((span) {
          expect(span.style?.backgroundColor, isNull);
          return true;
        });
      }
    });

    testWidgets('reduce motion: folds without animating', (tester) async {
      await open(
        tester,
        done(sections(4, extras: true), from: four),
        reduce: true,
      );
      expect(find.byType(AnimatedSize), findsNothing);
      await tester.tap(chip('Istilah'));
      await tester.pump();
      expect(panel(), findsNothing);
    });
  });

  group('Nyambung ke (#65)', () {
    const xvii = (chapterId: 17, groupIndex: 0);
    const next = (chapterId: 10, groupIndex: 1);
    final linked = done(
      Breakdown(
        sections: two.sections,
        links: const [
          BreakdownLink(chapter: 2, title: 'Metafora aktor', why: 'Peran.'),
          BreakdownLink(title: 'Dari ayahnya', why: 'Utang budi.'),
        ],
      ),
    );
    Finder card(String where) =>
        find.ancestor(of: find.text(where), matching: find.byType(InkWell));
    Future<void> peek(WidgetTester tester, String where) async {
      await tester.scrollUntilVisible(
        find.text(where),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text(where));
      await tester.pumpAndSettle();
    }

    testWidgets('a card with a target is tappable, one without is plain', (
      tester,
    ) async {
      peeks = {
        2: const BreakdownPeek(group: xvii, original: ['Remember.']),
      };
      await open(tester, linked);
      await tester.scrollUntilVisible(
        find.text('XVII'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(card('XVII'), findsOneWidget);
      expect(card('LANJUTAN XXIV'), findsNothing); // no next group
    });

    testWidgets('1a translated: translation, original below, only '
        '"Bedahin ini juga"', (tester) async {
      peeks = {
        2: const BreakdownPeek(
          group: xvii,
          original: ['Remember that you are an actor.'],
          translations: ['Ingat, kamu itu aktor.'],
        ),
      };
      await open(tester, linked);
      await peek(tester, 'XVII');
      expect(find.text('NYAMBUNG KE · AWAL XVII'), findsOneWidget);
      expect(find.text('Metafora aktor'), findsWidgets);
      expect(find.text('Peran.'), findsOneWidget);
      expect(find.text('Ingat, kamu itu aktor.'), findsOneWidget);
      expect(find.text('Remember that you are an actor.'), findsOneWidget);
      expect(find.text('Artiin'), findsNothing);
      expect(find.text('Bedahin ini juga'), findsOneWidget);
    });

    testWidgets('1b next group: its own header', (tester) async {
      peeks = {
        null: const BreakdownPeek(group: next, original: ['From my father.']),
      };
      await open(tester, linked);
      await peek(tester, 'LANJUTAN XXIV');
      expect(find.text('LANJUTAN XXIV · GRUP BERIKUTNYA'), findsOneWidget);
      expect(find.text('From my father.'), findsOneWidget);
    });

    testWidgets('1c → 1d: Artiin streams over the original, then is gone', (
      tester,
    ) async {
      peeks = {
        2: const BreakdownPeek(group: xvii, original: ['Remember.']),
      };
      await open(tester, linked);
      await peek(tester, 'XVII');
      expect(find.text('Artiin'), findsOneWidget);
      expect(FakeArtiin.live, isEmpty); // nothing asked yet

      await tester.tap(find.text('Artiin'));
      await tester.pump();
      expect(FakeArtiin.live.keys, [xvii]);
      expect(find.text('Lagi mikir'), findsOneWidget);
      FakeArtiin.live[xvii]!.push(
        const AiStream(
          phase: AiPhase.translating,
          draft: AiDraft(translations: ['Ingat, kamu']),
        ),
      );
      await tester.pump();
      expect(find.text('Lagi nulis'), findsOneWidget);
      expect(find.textContaining('Ingat'), findsOneWidget);
      FakeArtiin.live[xvii]!.push(
        const AiStream(
          phase: AiPhase.done,
          draft: AiDraft(translations: ['Ingat, kamu aktor.'], meaning: 'M'),
        ),
      );
      await tester.pump();
      expect(find.text('Ingat, kamu aktor.'), findsOneWidget);
      expect(find.text('Artiin'), findsNothing);
      expect(find.text('Remember.'), findsOneWidget);
    });

    testWidgets('Artiin failed: a pink row, "Coba artiin lagi"', (
      tester,
    ) async {
      peeks = {
        2: const BreakdownPeek(group: xvii, original: ['Remember.']),
      };
      await open(tester, linked);
      await peek(tester, 'XVII');
      await tester.tap(find.text('Artiin'));
      await tester.pump();
      FakeArtiin.live[xvii]!.push(
        const AiStream(
          phase: AiPhase.failed,
          error: AiException(AiError.network),
        ),
      );
      await tester.pump();
      expect(find.text('Yah, gagal ngartiin'), findsOneWidget);
      expect(find.text('Remember.'), findsOneWidget);
      await tester.tap(find.text('Coba artiin lagi'));
      await tester.pump();
      expect(find.text('Lagi mikir'), findsOneWidget);
    });

    testWidgets('key rejected: row links to Settings', (tester) async {
      peeks = {
        2: const BreakdownPeek(group: xvii, original: ['Remember.']),
      };
      await open(tester, linked);
      await peek(tester, 'XVII');
      await tester.tap(find.text('Artiin'));
      await tester.pump();
      FakeArtiin.live[xvii]!.push(
        const AiStream(
          phase: AiPhase.failed,
          error: AiException(AiError.http, status: 401),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Buka Pengaturan'));
      await tester.pumpAndSettle();
      expect(find.text('Pengaturan'), findsOneWidget);
    });

    testWidgets('"Bedahin ini juga" stacks a layer: back steps one, '
        '"Balik baca" closes them all', (tester) async {
      peeks = {
        2: const BreakdownPeek(
          group: xvii,
          original: ['Remember.'],
          translations: ['Ingat.'],
        ),
      };
      await open(tester, linked);
      final pixels = tester
          .state<ScrollableState>(find.byType(Scrollable).last)
          .position
          .pixels;
      await peek(tester, 'XVII');
      await tester.tap(find.text('Bedahin ini juga'));
      await tester.pumpAndSettle();
      expect(FakeBreakdown.live.keys, containsAll([g, xvii]));
      expect(find.text('Bedahin ini juga'), findsNothing); // sheet gone

      // Back: the first Bedahin, same scroll, no sheet.
      await tester.tap(find.bySemanticsLabel('Balik ke Artinya'));
      await tester.pumpAndSettle();
      expect(find.byType(BreakdownView), findsOneWidget);
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).last)
            .position
            .pixels,
        pixels,
      );
      expect(find.text('Bedahin ini juga'), findsNothing);

      // Again, then "Balik baca" from the top layer: all the way out.
      await peek(tester, 'XVII');
      await tester.tap(find.text('Bedahin ini juga'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Balik baca'));
      await tester.pumpAndSettle();
      expect(find.byType(BreakdownView), findsNothing);
      expect(popped, isTrue);
    });

    testWidgets('"Bedahin ini juga" before Artiin: translates, then goes', (
      tester,
    ) async {
      peeks = {
        2: const BreakdownPeek(group: xvii, original: ['Remember.']),
      };
      await open(tester, linked);
      await peek(tester, 'XVII');
      await tester.tap(find.text('Bedahin ini juga'));
      await tester.pump();
      expect(find.text('Lagi mikir'), findsOneWidget);
      FakeArtiin.live[xvii]!.push(
        const AiStream(
          phase: AiPhase.done,
          draft: AiDraft(translations: ['Ingat.'], meaning: 'M'),
        ),
      );
      await tester.pumpAndSettle();
      expect(FakeBreakdown.live.keys, contains(xvii));
    });
  });

  testWidgets('reduce motion: whole sections only while writing', (
    tester,
  ) async {
    await open(tester, BreakdownState(input: onePara), reduce: true);
    fake().push(
      BreakdownState(
        phase: BreakdownPhase.writing,
        input: onePara,
        draft: Breakdown(
          sections: [
            section(1, 2, 'satu'),
            const BreakdownSection(from: 3, to: 4, title: 'Setengah'),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Logika satu.'), findsOneWidget); // whole, at once
    expect(find.text('Setengah'), findsNothing); // still being written
  });
}
