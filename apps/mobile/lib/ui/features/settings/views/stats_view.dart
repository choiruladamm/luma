import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../../../data/repositories/stats_repository.dart';
import '../../../../domain/reading_stats.dart';
import '../../../../l10n/l10n.dart';
import '../../../core/format.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import 'settings_page.dart';

/// Settings · Statistik baca: the screen each reading statistic adds a card
/// to. Not on the design board; built from the Settings detail cards.
class StatsView extends ConsumerWidget {
  const StatsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final locale = l.localeName;
    final summary = ref.watch(readingSummaryProvider).value;
    final habits = ref.watch(habitStatsProvider).value;
    final books = ref.watch(bookStatsProvider).value ?? const <BookStats>[];
    final reading = books.where((b) => b.finishedAt == null).take(_listMax);
    final finished = books.where((b) => b.finishedAt != null).take(_listMax);
    final costs = ref.watch(costStatsProvider).value;
    String time(int seconds) => formatReadingTime(seconds, locale: locale);
    return SettingsPage(
      title: l.statsTitle,
      children: [
        if (summary == null)
          const SizedBox.shrink()
        else if (summary.isEmpty)
          const _EmptyCard()
        else ...[
          if (habits != null) ...[
            _NumbersCard(
              title: l.statsHabit,
              numbers: [
                (l.statsThisWeek, time(habits.thisWeek)),
                (l.statsStreak, l.statsStreakDays(habits.streak)),
              ],
              note: l.statsLastWeek(time(habits.lastWeek)),
            ),
            _CalendarCard(perDay: habits.perDay),
            if (_favorite(context, habits) case final numbers?)
              _NumbersCard(title: l.statsFavorite, numbers: numbers),
          ],
          if (reading.isNotEmpty)
            _BooksCard(
              title: l.statsReadingNow,
              rows: [
                for (final b in reading)
                  (
                    b.title,
                    b.charsPerMinute == null
                        ? l.statsBookPercent((b.progress * 100).round())
                        : l.statsBookProgress(
                            (b.progress * 100).round(),
                            thousands(
                              b.charsPerMinute!.round(),
                              locale: locale,
                            ),
                          ),
                    b.remaining == null
                        ? '—'
                        : l.statsTimeLeft(time(b.remaining!.inSeconds)),
                  ),
              ],
            ),
          if (finished.isNotEmpty)
            _BooksCard(
              title: l.statsFinishedList,
              rows: [
                for (final b in finished)
                  (
                    b.title,
                    l.statsFinishedOn(date(b.finishedAt!, locale: locale)),
                    '',
                  ),
              ],
            ),
          if (costs != null && costs.features.isNotEmpty)
            _costCard(context, costs),
          _NumbersCard(
            title: l.statsAllTime,
            numbers: [
              (l.statsReadingTime, time(summary.totalSeconds)),
              (
                l.statsFinished,
                thousands(summary.finishedBooks, locale: locale),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Books listed per progress card.
const _listMax = 5;

// The app's AI feature names; product names, so the same in every language.
const _features = {
  'group': 'Artinya',
  'breakdown': 'Bedahin',
  'chat': 'Ngobrolin',
};

/// AI cost per month, feature, and book. A cost no call reported shows as
/// "Gak tercatat", never as zero.
Widget _costCard(BuildContext context, CostStats costs) {
  final l = context.l10n;
  final locale = l.localeName;
  (String, String, String) row(String name, CostRow r) => (
    name,
    l.statsCalls(r.calls),
    r.costUsd == null ? l.statsCostUnrecorded : usd(r.costUsd!, locale: locale),
  );
  final month = DateFormat.yMMMM(locale);
  return _BooksCard(
    title: l.statsCost,
    note: l.statsCostNote,
    sections: [
      (
        l.statsCostByMonth,
        [
          for (final r in costs.months)
            row(month.format(DateTime.parse('${r.key}-01')), r),
        ],
      ),
      (
        l.statsCostByFeature,
        [
          for (final r in costs.features)
            row(_features[r.key] ?? '${r.key}', r),
        ],
      ),
      (
        l.statsCostByBook,
        [for (final r in costs.books) row(r.key ?? l.statsDeletedBook, r)],
      ),
    ],
  );
}

/// The busiest hour ("21.00–22.00") and weekday; null before any reading.
List<(String, String)>? _favorite(BuildContext context, HabitStats habits) {
  final hour = busiest(habits.perHour);
  final day = busiest(habits.perWeekday);
  if (hour == null || day == null) return null;
  final l = context.l10n;
  final hm = DateFormat.Hm(l.localeName);
  // 2024-01-01 is a Monday, so day index 0..6 maps onto it.
  final range = l.statsHourRange(
    hm.format(DateTime(2024, 1, 1, hour)),
    hm.format(DateTime(2024, 1, 1, hour + 1)),
  );
  final weekday = DateFormat.EEEE(l.localeName)
      .format(DateTime(2024, 1, 1 + day));
  return [(l.statsFavoriteHour, range), (l.statsFavoriteDay, weekday)];
}

BoxDecoration _card(StabiloColors c) => BoxDecoration(
  color: c.sheet,
  borderRadius: BorderRadius.circular(Radii.lg),
  border: Border.all(color: c.menuLine),
);

/// A titled card with numbers side by side.
class _NumbersCard extends StatelessWidget {
  const _NumbersCard({required this.title, required this.numbers, this.note});

  final String title;
  final List<(String label, String value)> numbers;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: _card(c),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.s3,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: StabiloType.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: c.ink2,
              ),
            ),
          ),
          Row(
            spacing: Space.s3,
            children: [
              for (final (label, value) in numbers)
                Expanded(
                  child: MergeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(
                          value,
                          style: StabiloType.titleMd.copyWith(color: c.ink),
                        ),
                        Text(
                          label,
                          style: StabiloType.caption.copyWith(color: c.ink2),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (note case final note?)
            Text(note, style: StabiloType.caption.copyWith(color: c.ink2)),
        ],
      ),
    );
  }
}

/// A GitHub-style grid: one column per week (Monday on top), one square per
/// day, darker for more reading. Intensity is relative to the busiest day.
class _CalendarCard extends StatelessWidget {
  const _CalendarCard({required this.perDay});

  final Map<DateTime, int> perDay;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final l = context.l10n;
    final today = localDay(DateTime.now());
    final first = weekStart(today);
    final start = DateTime(
      first.year,
      first.month,
      first.day - 7 * (StatsRepository.calendarWeeks - 1),
    );
    final max = perDay.values.fold(0, (a, b) => b > a ? b : a);
    final days = perDay.values.where((s) => s > 0).length;
    Color shade(int seconds) {
      if (seconds <= 0 || max == 0) return c.track;
      // Four steps, so a light day still shows.
      final step = (seconds / max * 4).ceil().clamp(1, 4);
      return c.accent.withValues(alpha: step / 4);
    }

    Widget cell(DateTime day) => Container(
      width: Calendar.day,
      height: Calendar.day,
      decoration: BoxDecoration(
        color: day.isAfter(today)
            ? Colors.transparent
            : shade(perDay[day] ?? 0),
        borderRadius: BorderRadius.circular(Radii.calendarDay),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: _card(c),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.s3,
        children: [
          Semantics(
            header: true,
            child: Text(
              l.statsCalendar,
              style: StabiloType.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: c.ink2,
              ),
            ),
          ),
          // The caption below says the same for screen readers.
          ExcludeSemantics(
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Calendar.gap,
                children: [
                  for (var w = 0; w < StatsRepository.calendarWeeks; w++)
                    Column(
                      spacing: Calendar.gap,
                      children: [
                        for (var d = 0; d < 7; d++)
                          cell(
                            DateTime(
                              start.year,
                              start.month,
                              start.day + w * 7 + d,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          Text(
            l.statsCalendarLabel(days, StatsRepository.calendarWeeks),
            style: StabiloType.caption.copyWith(color: c.ink2),
          ),
        ],
      ),
    );
  }
}

/// A titled list of books: title and a caption on the left, a value on the right.
class _BooksCard extends StatelessWidget {
  const _BooksCard({
    required this.title,
    this.rows = const [],
    this.sections = const [],
    this.note,
  });

  final String title;
  final List<(String title, String caption, String value)> rows;

  /// Titled groups of rows under [rows], for one card with several lists.
  final List<(String heading, List<(String, String, String)> rows)> sections;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final heading = StabiloType.caption.copyWith(
      fontWeight: FontWeight.w700,
      color: c.ink2,
    );
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: _card(c),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.s3,
        children: [
          Semantics(header: true, child: Text(title, style: heading)),
          if (note case final note?)
            Text(note, style: StabiloType.caption.copyWith(color: c.ink2)),
          ..._rows(c, rows),
          for (final (name, group) in sections) ...[
            Padding(
              padding: const EdgeInsets.only(top: Space.s1),
              child: Semantics(
                header: true,
                child: Text(
                  name,
                  style: StabiloType.label.copyWith(color: c.ink2),
                ),
              ),
            ),
            ..._rows(c, group),
          ],
        ],
      ),
    );
  }

  static Iterable<Widget> _rows(
    StabiloColors c,
    List<(String, String, String)> rows,
  ) sync* {
    for (final (name, caption, value) in rows) {
      yield MergeSemantics(
        child: Row(
          spacing: Space.s3,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: StabiloType.label.copyWith(color: c.ink),
                  ),
                  Text(
                    caption,
                    style: StabiloType.caption.copyWith(color: c.ink2),
                  ),
                ],
              ),
            ),
            if (value.isNotEmpty)
              Text(value, style: StabiloType.caption.copyWith(color: c.ink)),
          ],
        ),
      );
    }
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final l = context.l10n;
    return Container(
      padding: const EdgeInsets.all(Space.s5),
      decoration: _card(c),
      child: Column(
        spacing: Space.s3,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: c.muted, shape: BoxShape.circle),
            child: Center(
              child: AppIcon(
                HugeIcons.strokeRoundedChart01,
                size: 22,
                color: c.ink,
              ),
            ),
          ),
          Text(
            l.statsEmptyTitle,
            style: StabiloType.titleSm.copyWith(color: c.ink),
            textAlign: TextAlign.center,
          ),
          Text(
            l.statsEmptyBody,
            style: StabiloType.caption.copyWith(color: c.ink2),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
