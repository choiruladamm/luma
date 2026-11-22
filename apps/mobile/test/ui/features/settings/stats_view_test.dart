import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/stats_repository.dart';
import 'package:luma/l10n/app_localizations.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/features/settings/views/stats_view.dart';

const noHabits = HabitStats(
  thisWeek: 0,
  lastWeek: 0,
  streak: 0,
  perDay: {},
  perHour: [
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ],
  perWeekday: [0, 0, 0, 0, 0, 0, 0],
);

void main() {
  Future<void> open(
    WidgetTester tester,
    ReadingSummary summary, {
    Brightness b = Brightness.light,
    HabitStats habits = noHabits,
    List<BookStats> books = const [],
  }) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          readingSummaryProvider.overrideWith((_) => Stream.value(summary)),
          habitStatsProvider.overrideWith((_) => Stream.value(habits)),
          bookStatsProvider.overrideWith((_) => Stream.value(books)),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('id'),
          theme: stabiloTheme(b),
          home: const StatsView(),
        ),
      ),
    );
    await tester.pump();
  }

  for (final b in Brightness.values) {
    testWidgets('habits, calendar, favorite times, and all time ($b)', (
      tester,
    ) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final hours = List.filled(24, 0)..[21] = 900;
      await open(
        tester,
        const ReadingSummary(
          weekSeconds: 4500,
          totalSeconds: 36000,
          finishedBooks: 2,
        ),
        b: b,
        habits: HabitStats(
          thisWeek: 4500,
          lastWeek: 600,
          streak: 3,
          perDay: {today: 600, today.subtract(const Duration(days: 1)): 60},
          perHour: hours,
          perWeekday: const [0, 0, 0, 0, 0, 0, 900],
        ),
      );
      expect(find.text('Statistik baca'), findsOneWidget);
      expect(find.text('1 jam 15 mnt'), findsOneWidget);
      expect(find.text('3 hari'), findsOneWidget);
      expect(find.text('Minggu lalu 10 mnt'), findsOneWidget);
      expect(find.text('2 hari baca dalam 18 minggu terakhir'), findsOneWidget);
      expect(find.text('21.00–22.00'), findsOneWidget);
      expect(find.text('Minggu'), findsOneWidget);
      expect(find.text('10 jam 0 mnt'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('no favorite card before any reading time', (tester) async {
    await open(
      tester,
      const ReadingSummary(weekSeconds: 0, totalSeconds: 0, finishedBooks: 1),
    );
    expect(find.text('Paling sering baca'), findsNothing);
    expect(find.text('Kalender baca'), findsOneWidget);
  });

  testWidgets('empty state before any reading', (tester) async {
    await open(
      tester,
      const ReadingSummary(weekSeconds: 0, totalSeconds: 0, finishedBooks: 0),
    );
    expect(find.text('Belum ada statistik'), findsOneWidget);
    expect(find.text('7 hari terakhir'), findsNothing);
  });

  testWidgets('reading now with an estimate, and finished books', (
    tester,
  ) async {
    await open(
      tester,
      const ReadingSummary(
        weekSeconds: 60,
        totalSeconds: 600,
        finishedBooks: 1,
      ),
      books: [
        BookStats(
          bookId: 1,
          title: 'Meditations',
          progress: 0.42,
          charsPerMinute: 900,
          remaining: const Duration(minutes: 75),
          finishedAt: null,
        ),
        const BookStats(
          bookId: 3,
          title: 'Catatan',
          progress: 0.1,
          charsPerMinute: null,
          remaining: null,
          finishedAt: null,
        ),
        BookStats(
          bookId: 2,
          title: 'Atomic Habits',
          progress: 1,
          charsPerMinute: 1000,
          remaining: null,
          finishedAt: DateTime(2026, 11, 10),
        ),
      ],
    );
    expect(find.text('Lagi dibaca'), findsOneWidget);
    expect(find.text('42% · 900 karakter/mnt'), findsOneWidget);
    expect(find.text('±1 jam 15 mnt lagi'), findsOneWidget);
    expect(find.text('10%'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('Udah tamat'), findsOneWidget);
    expect(find.text('Atomic Habits'), findsOneWidget);
    expect(find.textContaining('Tamat 10'), findsOneWidget);
  });
}
