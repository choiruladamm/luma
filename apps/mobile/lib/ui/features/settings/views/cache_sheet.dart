import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/ai_breakdowns_repository.dart';
import '../../../../data/repositories/ai_results_repository.dart';
import '../../../../l10n/l10n.dart';
import '../../../core/format.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/sheet.dart';

/// Sheet "Hapus cache terjemahan?" (board Atur · Cache): isi cache + konfirmasi
/// dalam satu langkah. Tombol Hapus nyalain dua repo sekaligus lalu nutup.
Future<void> showCacheSheet(BuildContext context) =>
    showAppSheet<void>(context, builder: (_) => const _CacheSheet());

class _CacheSheet extends ConsumerWidget {
  const _CacheSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.stabilo;
    final locale = context.l10n.localeName;
    final stats = ref.watch(aiCacheStatsProvider).value;
    final empty = stats == null || stats.paragraphs == 0;

    Future<void> clear() async {
      final results = ref.read(aiResultsRepositoryProvider);
      final breakdowns = ref.read(aiBreakdownsRepositoryProvider);
      Navigator.of(context).pop();
      await results.clear();
      await breakdowns.clear();
    }

    return SheetFrame(
      actions: [
        Expanded(
          child: Column(
            spacing: Space.s2,
            children: [
              AppButton.danger(
                label: context.l10n.settingsCacheClear,
                icon: AppIcons.delete,
                height: 52,
                soft: true,
                onPressed: empty ? null : clear,
              ),
              AppButton.secondary(
                label: context.l10n.settingsCacheCancel,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ],
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.s1,
          children: [
            Text(
              context.l10n.settingsCacheEyebrow,
              style: StabiloType.caption.copyWith(color: c.ink2),
            ),
            Semantics(
              header: true,
              child: Text(
                context.l10n.settingsCacheTitle,
                style: StabiloType.titleMd,
              ),
            ),
          ],
        ),
        Row(
          spacing: Space.s2 + 2,
          children: [
            Expanded(
              child: _Stat(
                value: stats == null
                    ? ' '
                    : thousands(stats.paragraphs, locale: locale),
                label: context.l10n.settingsCacheParagraphs,
              ),
            ),
            Expanded(
              child: _Stat(
                value: stats == null
                    ? ' '
                    : fileSize(stats.bytes, locale: locale),
                label: context.l10n.settingsCacheUsed,
              ),
            ),
          ],
        ),
        Text(
          context.l10n.settingsCacheBody,
          style: StabiloType.readingSheet.copyWith(color: c.ink),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: Space.s3),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(Radii.field),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: StabiloType.titleSm.copyWith(
              fontSize: 20,
              letterSpacing: -0.4,
              color: c.ink,
            ),
          ),
          Text(
            label,
            style: StabiloType.caption.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w400,
              color: c.ink2,
            ),
          ),
        ],
      ),
    );
  }
}
