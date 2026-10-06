import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../theme/stabilo_theme.dart';
import '../theme/stabilo_tokens.dart';
import '../theme/stabilo_type.dart';

/// Ikon Hugeicons Stroke Rounded. Warna ikut `IconTheme` / teks di sekitarnya.
class AppIcon extends StatelessWidget {
  const AppIcon(this.icon, {super.key, this.size = Layout.icon, this.color});

  final List<List<dynamic>> icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => HugeIcon(
    icon: icon,
    size: size,
    color: color,
    strokeWidth: size <= 14 ? 2.2 : Layout.iconStroke,
  );
}

enum _Tone { primary, secondary, danger }

/// Tombol Stabilo (board Komponen 01).
///
/// - [AppButton.primary]: accent + outline + press shadow. Satu layar
///   maksimal satu.
/// - [AppButton.secondary]: muted. [destructive] = teks merah (mis. "Hapus"
///   cache).
/// - [AppButton.danger]: latar danger, buat konfirmasi hapus/ganti data.
///
/// Tinggi: 56 = CTA layar (sudut 20), 52 = aksi di sheet, 48 = dialog &
/// state sheet, 40 = aksi kecil di baris/toast. Di bawah 56 bentuknya pill.
/// `onPressed: null` = disabled.
class AppButton extends StatelessWidget {
  const AppButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 52,
  }) : _tone = _Tone.primary,
       destructive = false;

  const AppButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 52,
    this.destructive = false,
  }) : _tone = _Tone.secondary;

  const AppButton.danger({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 48,
  }) : _tone = _Tone.danger,
       destructive = true;

  final String label;
  final VoidCallback? onPressed;
  final List<List<dynamic>>? icon;
  final double height;
  final bool destructive;
  final _Tone _tone;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final enabled = onPressed != null;
    final primary = _tone == _Tone.primary;
    final radius = BorderRadius.circular(height >= 56 ? Radii.lg : Radii.full);

    final (bg, fg) = switch (_tone) {
      _ when !enabled => (primary ? c.track : c.muted, c.ink3),
      _Tone.primary => (c.accent, c.onAccent),
      _Tone.secondary => (c.muted, destructive ? c.danger : c.ink),
      _Tone.danger => (c.danger, c.onDanger),
    };
    final fontSize = height >= 56 ? 16.0 : (height <= 48 ? 14.0 : 15.0);

    return Semantics(
      button: true,
      enabled: enabled,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: primary && enabled
              ? Elevation.press(c, Theme.of(context).brightness)
              : null,
        ),
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: primary && enabled
                ? BorderSide(color: c.accentBorder, width: Layout.outline)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              height: height,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: height >= 56 ? Space.s6 : Space.s4,
                ),
                child: IconTheme.merge(
                  data: IconThemeData(color: fg),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: Space.s2,
                    children: [
                      if (icon != null) AppIcon(icon!, size: fontSize + 4),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: StabiloType.label.copyWith(
                            fontSize: fontSize,
                            color: fg,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tombol bulet 44 (target sentuh minimal). [active] = accent, mis. Aa pas
/// sheet-nya kebuka. [primary] = aksi utama layar (accent + outline + press
/// shadow, mis. Import di rak). Isi: [icon] atau [text] ("Aa", "A").
class CircleButton extends StatelessWidget {
  const CircleButton({
    super.key,
    required this.semanticLabel,
    required this.onPressed,
    this.icon,
    this.text,
    this.active = false,
    this.primary = false,
    this.size = Layout.touch,
  }) : assert((icon == null) != (text == null));

  final String semanticLabel;
  final VoidCallback? onPressed;
  final List<List<dynamic>>? icon;
  final String? text;
  final bool active;
  final bool primary;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final accent = active || primary;
    final fg = onPressed == null ? c.ink3 : (accent ? c.onAccent : c.ink);
    final button = Material(
      color: accent ? c.accent : c.muted,
      shape: primary
          ? CircleBorder(
              side: BorderSide(color: c.accentBorder, width: Layout.outline),
            )
          : const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: icon != null
                ? AppIcon(icon!, color: fg)
                : Text(
                    text!,
                    style: StabiloType.label.copyWith(fontSize: 16, color: fg),
                  ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: primary
          ? DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: Elevation.press(c, Theme.of(context).brightness),
              ),
              child: button,
            )
          : button,
    );
  }
}

/// Ikon yang sering dipake, biar nama Hugeicons-nya gak nyebar.
abstract final class AppIcons {
  static const back = HugeIcons.strokeRoundedArrowLeft01;
  static const close = HugeIcons.strokeRoundedCancel01;
  static const check = HugeIcons.strokeRoundedTick02;
  static const show = HugeIcons.strokeRoundedView;
  static const hide = HugeIcons.strokeRoundedViewOff;
  static const loading = HugeIcons.strokeRoundedLoading03;
  static const add = HugeIcons.strokeRoundedAdd01;
  static const settings = HugeIcons.strokeRoundedSettings01;
}
