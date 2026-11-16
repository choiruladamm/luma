import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/settings_repository.dart';
import '../../../../domain/models/reader_prefs.dart';
import '../../../../l10n/l10n.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/sheet.dart';
import '../../../core/widgets/toast.dart';

/// Sheet "Tampilan" (board Atur · Bahasa): tema (setelan yang sama dengan
/// menu Aa di layar baca) + bahasa tampilan. Pilihan langsung disimpen.
Future<void> showDisplaySheet(BuildContext context) =>
    showAppSheet<void>(context, builder: (_) => const _DisplaySheet());

class _DisplaySheet extends ConsumerStatefulWidget {
  const _DisplaySheet();

  @override
  ConsumerState<_DisplaySheet> createState() => _DisplaySheetState();
}

class _DisplaySheetState extends ConsumerState<_DisplaySheet> {
  bool _saving = false;

  Future<void> _setLanguage(String language) async {
    setState(() => _saving = true);
    try {
      await ref.read(settingsRepositoryProvider).saveLocale(language);
    } catch (_) {
      if (mounted) showToast(context, context.l10n.languageSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final prefs = ref.watch(readerPrefsProvider).value ?? const ReaderPrefs();
    final language = ref.watch(appLocaleProvider).value ?? 'id';
    final note = StabiloType.caption.copyWith(
      fontSize: 12.5,
      height: 1.4,
      fontWeight: FontWeight.w400,
      color: c.ink2,
    );
    final label = StabiloType.caption.copyWith(color: c.ink2);
    return SheetFrame(
      title: context.l10n.settingsDisplayTitle,
      children: [
        Text(context.l10n.settingsDisplayTheme, style: label),
        Row(
          spacing: Space.s2,
          children: [
            for (final (theme, title, hint) in [
              (
                AppTheme.system,
                context.l10n.aaSystem,
                context.l10n.settingsDisplaySystemHint,
              ),
              (
                AppTheme.light,
                context.l10n.aaLight,
                context.l10n.settingsDisplayLightHint,
              ),
              (
                AppTheme.dark,
                context.l10n.aaDark,
                context.l10n.settingsDisplayDarkHint,
              ),
            ])
              Expanded(
                child: _ThemeCard(
                  theme: theme,
                  title: title,
                  hint: hint,
                  selected: prefs.theme == theme,
                  onTap: () => ref
                      .read(settingsRepositoryProvider)
                      .saveReaderPrefs(prefs.copyWith(theme: theme)),
                ),
              ),
          ],
        ),
        Text(context.l10n.settingsDisplayThemeNote, style: note),
        Padding(
          padding: const EdgeInsets.only(top: Space.s1),
          child: Text(
            context.l10n.settingsDisplayLanguage,
            style: label.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Container(
          height: 46,
          padding: const EdgeInsets.all(Space.s1),
          decoration: BoxDecoration(
            color: c.muted,
            borderRadius: BorderRadius.circular(Radii.full),
          ),
          child: Row(
            spacing: Space.s1,
            children: [
              for (final (code, name) in const [
                ('id', 'Bahasa Indonesia'),
                ('en', 'English'),
              ])
                Expanded(
                  child: _Segment(
                    label: name,
                    selected: language == code,
                    onTap: _saving ? null : () => _setLanguage(code),
                  ),
                ),
            ],
          ),
        ),
        Text(context.l10n.settingsDisplayLanguageNote, style: note),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: selected ? null : onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.sheet : null,
            borderRadius: BorderRadius.circular(Radii.full),
            border: selected
                ? Border.all(color: c.outline, width: Layout.outline)
                : null,
          ),
          child: Text(
            label,
            style: StabiloType.label.copyWith(
              fontSize: 14,
              color: selected ? c.ink : c.ink2,
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.theme,
    required this.title,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final AppTheme theme;
  final String title;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: title,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: Space.s3,
            horizontal: 10,
          ),
          decoration: BoxDecoration(
            color: c.sheet,
            borderRadius: BorderRadius.circular(Radii.menu),
            border: Border.all(
              color: selected ? c.outline : c.menuLine,
              width: selected ? Layout.outline : 1,
            ),
          ),
          child: Column(
            spacing: Space.s2,
            children: [
              _Thumb(theme),
              Column(
                spacing: 1,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: StabiloType.label.copyWith(
                      fontSize: 14,
                      color: c.ink,
                    ),
                  ),
                  Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: StabiloType.caption.copyWith(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w400,
                      color: c.ink2,
                    ),
                  ),
                ],
              ),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? c.outline : null,
                  border: selected
                      ? null
                      : Border.all(color: c.fieldLine, width: Layout.outline),
                ),
                child: selected
                    ? Center(
                        child: AppIcon(
                          AppIcons.check,
                          size: 13,
                          color: c.sheet,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Layar mini: terang, gelap, atau terang dipotong diagonal dengan gelap
/// (Ikut sistem). Selalu pake palet tema masing-masing, bukan tema aktif.
class _Thumb extends StatelessWidget {
  const _Thumb(this.theme);

  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Container(
      width: 64,
      height: 92,
      // Garis di depan (bukan di dalam) biar layar mini tetap 64×92 penuh.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: c.menuLine),
      ),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.sm)),
      clipBehavior: Clip.antiAlias,
      child: ExcludeSemantics(
        child: switch (theme) {
          AppTheme.light => const _Screen(StabiloColors.light),
          AppTheme.dark => const _Screen(StabiloColors.dark),
          AppTheme.system => Stack(
            fit: StackFit.expand,
            children: [
              const _Screen(StabiloColors.light),
              ClipPath(
                clipper: _LowerRight(),
                child: const _Screen(StabiloColors.dark),
              ),
            ],
          ),
        },
      ),
    );
  }
}

class _LowerRight extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(_LowerRight oldClipper) => false;
}

class _Screen extends StatelessWidget {
  const _Screen(this.p);

  final StabiloColors p;

  @override
  Widget build(BuildContext context) {
    Widget box(double h, {double radius = 4}) => Container(
      height: h,
      decoration: BoxDecoration(
        color: p.sheet,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: p.menuLine),
      ),
    );
    return Container(
      color: p.canvas,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
      child: Column(
        spacing: 5,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 5,
            decoration: BoxDecoration(
              color: p.ink,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          box(26, radius: 6),
          Row(
            spacing: Space.s1,
            children: [
              Expanded(child: box(14)),
              Expanded(child: box(14)),
            ],
          ),
          const Spacer(),
          Align(
            alignment: Alignment.center,
            child: SizedBox(width: 37, child: box(8)),
          ),
        ],
      ),
    );
  }
}
