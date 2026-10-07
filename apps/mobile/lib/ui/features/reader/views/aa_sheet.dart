import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/settings_repository.dart';
import '../../../../domain/models/reader_prefs.dart';
import '../../../core/theme/reader_typography.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/sheet.dart';
import '../../../core/widgets/switch.dart';
import '../../../core/widgets/edge_fade.dart';

/// Atur bacaan (board 07 Atur bacaan). Tiap pilihan langsung disimpen dan
/// langsung keliatan di teks di belakang sheet (scrim-nya tipis). Kayak
/// daftar isi: kapsul atas tetep keliatan, barrier sheet transparan.
Future<void> showAaSheet(BuildContext context) {
  final height = MediaQuery.sizeOf(context).height;
  // Board: sheet mulai 238 di iPhone (safe area 54), teks bab pertama masih
  // keliatan buat preview.
  final top = MediaQuery.paddingOf(context).top + 184;
  return showAppSheet<void>(
    context,
    maxHeight: (height - top) / height,
    barrierColor: Colors.transparent,
    builder: (_) => const _AaSheet(),
  );
}

class _AaSheet extends ConsumerWidget {
  const _AaSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.stabilo;
    final prefs = ref.watch(readerPrefsProvider).value ?? const ReaderPrefs();
    void set(ReaderPrefs p) =>
        ref.read(settingsRepositoryProvider).saveReaderPrefs(p).ignore();

    // Tanpa tombol aksi: isi jalan sampe tepi bawah, tanpa fade bawah.
    return Padding(
      padding: Layout.sheetPadding.copyWith(bottom: 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.s4,
        children: [
          const SheetGrabber(),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('Atur bacaan lo', style: StabiloType.titleMd),
                ),
              ),
              CircleButton(
                semanticLabel: 'Tutup',
                icon: AppIcons.close,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          Flexible(
            child: EdgeFadeScroll(
              bottom: EdgeFadeSide.none,
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(context).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Space.s4,
                  children: [
                    _Section(
                      label: 'Ukuran huruf',
                      value: _decimal(prefs.fontSize),
                      child: _SizeStepper(
                        step: prefs.sizeStep,
                        onChanged: (s) => set(prefs.copyWith(sizeStep: s)),
                      ),
                    ),
                    _Section(
                      label: 'Font',
                      child: Row(
                        spacing: Space.s2,
                        children: [
                          for (final (font, label) in const [
                            (ReadingFont.clear, 'Jelas'),
                            (ReadingFont.book, 'Kayak buku'),
                            (ReadingFont.system, 'Bawaan iOS'),
                          ])
                            Expanded(
                              child: _FontTile(
                                label: label,
                                family: readingFamily(font),
                                selected: prefs.font == font,
                                onTap: () => set(prefs.copyWith(font: font)),
                              ),
                            ),
                        ],
                      ),
                    ),
                    _Section(
                      label: 'Jarak baris',
                      child: _Segmented(
                        options: const ['Rapat', 'Pas', 'Lega'],
                        selected: prefs.spacing.index,
                        onChanged: (i) =>
                            set(prefs.copyWith(spacing: LineSpacing.values[i])),
                      ),
                    ),
                    _Section(
                      label: 'Margin',
                      child: _Segmented(
                        options: const ['Sempit', 'Pas', 'Lega'],
                        selected: prefs.margin.index,
                        onChanged: (i) =>
                            set(prefs.copyWith(margin: TextMargin.values[i])),
                      ),
                    ),
                    _Section(
                      label: 'Tema',
                      child: Row(
                        spacing: Space.s2,
                        children: [
                          for (final (theme, label) in const [
                            (AppTheme.light, 'Terang'),
                            (AppTheme.dark, 'Gelap'),
                            (AppTheme.system, 'Ikut iOS'),
                          ])
                            Expanded(
                              child: _ThemePill(
                                theme: theme,
                                label: label,
                                selected: prefs.theme == theme,
                                onTap: () => set(prefs.copyWith(theme: theme)),
                              ),
                            ),
                        ],
                      ),
                    ),
                    _Section(
                      label: 'Tampilan layar',
                      child: Container(
                        decoration: BoxDecoration(
                          color: c.muted,
                          borderRadius: BorderRadius.circular(Radii.menu),
                        ),
                        child: Column(
                          children: [
                            _ToggleRow(
                              title: 'Sembunyiin jam & baterai',
                              subtitle: 'Status bar ngumpet bareng menu pas lagi baca',
                              value: prefs.hideStatusBar,
                              onChanged: (v) =>
                                  set(prefs.copyWith(hideStatusBar: v)),
                            ),
                            Divider(height: 1, thickness: 1, color: c.track),
                            _ToggleRow(
                              title: 'Tampilin garis progres',
                              subtitle:
                                  'Garis tipis di bawah layar pas menu ngumpet',
                              value: prefs.showProgressLine,
                              onChanged: (v) =>
                                  set(prefs.copyWith(showProgressLine: v)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 18.5 → "18,5", 20.0 → "20".
  static String _decimal(double v) => v == v.roundToDouble()
      ? '${v.round()}'
      : v.toString().replaceAll('.', ',');
}

class _Section extends StatelessWidget {
  const _Section({required this.label, this.value, required this.child});

  final String label;
  final String? value;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.s2,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: StabiloType.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: c.ink2,
                ),
              ),
            ),
            if (value != null)
              Text(
                value!,
                style: StabiloType.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: c.ink,
                ),
              ),
          ],
        ),
        child,
      ],
    );
  }
}

class _SizeStepper extends StatelessWidget {
  const _SizeStepper({required this.step, required this.onChanged});

  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final last = ReaderPrefs.sizes.length - 1;
    return Row(
      spacing: 10,
      children: [
        _LetterButton(
          label: 'Kecilin huruf',
          size: 14,
          onTap: step > 0 ? () => onChanged(step - 1) : null,
        ),
        Expanded(
          child: Row(
            spacing: 5,
            children: [
              for (var i = 0; i <= last; i++)
                Expanded(
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: i <= step ? c.ink : c.track,
                      borderRadius: BorderRadius.circular(Radii.full),
                    ),
                  ),
                ),
            ],
          ),
        ),
        _LetterButton(
          label: 'Gedein huruf',
          size: 21,
          onTap: step < last ? () => onChanged(step + 1) : null,
        ),
      ],
    );
  }
}

/// Tombol bulet 44 isinya huruf "A" kecil / gede.
class _LetterButton extends StatelessWidget {
  const _LetterButton({required this.label, required this.size, this.onTap});

  final String label;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: c.muted,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.square(
            dimension: Layout.touch,
            child: Center(
              child: Text(
                'A',
                style: StabiloType.label.copyWith(
                  fontSize: size,
                  height: 1,
                  color: onTap == null ? c.ink3 : c.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pilihan kuning bergaris (font, tema).
BoxDecoration _choice(StabiloColors c, bool selected, double radius) =>
    BoxDecoration(
      color: selected ? c.accent : c.muted,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: selected ? c.accentBorder : Colors.transparent,
        width: Layout.outline,
      ),
    );

class _FontTile extends StatelessWidget {
  const _FontTile({
    required this.label,
    required this.family,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String family;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final ink = selected ? c.onAccent : c.ink;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Font $label',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 74,
          decoration: _choice(c, selected, Radii.menu),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 2,
            children: [
              Text(
                'Aa',
                style: TextStyle(
                  fontFamily: family,
                  fontSize: 24,
                  height: 1.1,
                  color: ink,
                ),
              ),
              Text(
                label,
                style: StabiloType.tag.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                  color: ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final b = Theme.of(context).brightness;
    return Container(
      height: Layout.touch,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(Radii.full),
      ),
      child: Row(
        spacing: 3,
        children: [
          for (final (i, label) in options.indexed)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == selected,
                child: GestureDetector(
                  onTap: () => onChanged(i),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == selected ? c.segment : Colors.transparent,
                      borderRadius: BorderRadius.circular(Radii.full),
                      boxShadow: i == selected ? Elevation.segment(b) : null,
                    ),
                    child: Text(
                      label,
                      style: StabiloType.label.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ThemePill extends StatelessWidget {
  const _ThemePill({
    required this.theme,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final AppTheme theme;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    const light = StabiloColors.light;
    const dark = StabiloColors.dark;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Tema $label',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 48,
          decoration: _choice(c, selected, Radii.full),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: Space.s2,
            children: [
              // Contoh warna kanvas; "Ikut iOS" separo-separo.
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(
                      0x73808080,
                    ), // abu 45%, kebaca di dua tema
                    width: Layout.outline,
                  ),
                  color: switch (theme) {
                    AppTheme.light => light.canvas,
                    AppTheme.dark => dark.canvas,
                    AppTheme.system => null,
                  },
                  gradient: theme == AppTheme.system
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          stops: const [0.5, 0.5],
                          colors: [light.canvas, dark.canvas],
                        )
                      : null,
                ),
              ),
              Text(
                label,
                style: StabiloType.label.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected ? c.onAccent : c.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.s4, 10, 14, 10),
        child: Row(
          spacing: Space.s3,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    title,
                    style: StabiloType.label.copyWith(
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: StabiloType.caption.copyWith(
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: FontWeight.w400,
                      color: c.ink2,
                    ),
                  ),
                ],
              ),
            ),
            AppSwitch(value: value, onChanged: onChanged, semanticLabel: title),
          ],
        ),
      ),
    );
  }
}
