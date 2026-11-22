import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../../data/repositories/stats_repository.dart';
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
    final summary = ref.watch(readingSummaryProvider).value;
    return SettingsPage(
      title: l.statsTitle,
      children: [
        if (summary == null)
          const SizedBox.shrink()
        else if (summary.isEmpty)
          const _EmptyCard()
        else ...[
          _NumbersCard(
            title: l.statsWeek,
            numbers: [
              (
                l.statsReadingTime,
                formatReadingTime(summary.weekSeconds, locale: l.localeName),
              ),
              (l.statsReadingDays, l.statsDaysOfWeek(summary.weekDays)),
            ],
          ),
          _NumbersCard(
            title: l.statsAllTime,
            numbers: [
              (
                l.statsReadingTime,
                formatReadingTime(summary.totalSeconds, locale: l.localeName),
              ),
              (
                l.statsFinished,
                thousands(summary.finishedBooks, locale: l.localeName),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

BoxDecoration _card(StabiloColors c) => BoxDecoration(
  color: c.sheet,
  borderRadius: BorderRadius.circular(Radii.lg),
  border: Border.all(color: c.menuLine),
);

/// A titled card with numbers side by side.
class _NumbersCard extends StatelessWidget {
  const _NumbersCard({required this.title, required this.numbers});

  final String title;
  final List<(String label, String value)> numbers;

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
        ],
      ),
    );
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
