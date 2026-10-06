import 'package:flutter/material.dart';

import 'stabilo_tokens.dart';
import 'stabilo_type.dart';

/// Token warna Stabilo (board Foundations · 01 Warna). Satu nama, dua nilai.
@immutable
class StabiloColors extends ThemeExtension<StabiloColors> {
  const StabiloColors({
    required this.canvas,
    required this.sheet,
    required this.muted,
    required this.track,
    required this.outline,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.accent,
    required this.onAccent,
    required this.pink,
    required this.highlight,
    required this.onHighlight,
    required this.danger,
    required this.onDanger,
    required this.dangerSoft,
    required this.dangerInk,
    required this.toastBg,
    required this.toastInk,
    required this.mark,
    required this.scrim,
    required this.grabber,
  });

  // Permukaan
  final Color canvas, sheet, muted, track, outline;
  // Teks. ink3 khusus disabled.
  final Color ink, ink2, ink3;
  // Aksen. highlight cuma buat grup paragraf yang lagi dibuka di sheet.
  final Color accent, onAccent, pink, highlight, onHighlight;
  // Status & feedback. mark = penanda grup yang udah diterjemahin.
  final Color danger, onDanger, dangerSoft, dangerInk, toastBg, toastInk, mark;
  // Overlay
  final Color scrim, grabber;

  static const light = StabiloColors(
    canvas: Color(0xFFFFFBEF),
    sheet: Color(0xFFFFFDF6),
    muted: Color(0xFFF2EDDD),
    track: Color(0xFFE4DDC9),
    outline: Color(0xFF1A1A1A),
    ink: Color(0xFF1C1C1C),
    ink2: Color(0xFF5E5A4E),
    ink3: Color(0xFF8A8576),
    accent: Color(0xFFFFD84D),
    onAccent: Color(0xFF1A1A1A),
    pink: Color(0xFFFFC2D3),
    highlight: Color(0xFFFFD84D),
    onHighlight: Color(0xFF1A1A1A),
    danger: Color(0xFFB4361F),
    onDanger: Color(0xFFFFFBEF),
    dangerSoft: Color(0xFFF8E1DA),
    dangerInk: Color(0xFF8E2A17),
    toastBg: Color(0xFF1C1C1C),
    toastInk: Color(0xFFFFFBEF),
    mark: Color(0xFFE6B800),
    scrim: Color(0x611A1A1A), // 38%
    grabber: Color(0xFFE2DBC6),
  );

  static const dark = StabiloColors(
    canvas: Color(0xFF22201C),
    sheet: Color(0xFF2C2A25),
    muted: Color(0xFF36332D),
    track: Color(0xFF46423A),
    outline: Color(0xFF5A554B),
    ink: Color(0xFFDDD7C8),
    ink2: Color(0xFFA19B8E),
    ink3: Color(0xFF6E695E),
    accent: Color(0xFFE9C75A),
    onAccent: Color(0xFF22201C),
    pink: Color(0xFFD99BAE),
    highlight: Color(0x42E9C75A), // 26%
    onHighlight: Color(0xFFF3EBD3),
    danger: Color(0xFFE8836F),
    onDanger: Color(0xFF22201C),
    dangerSoft: Color(0xFF4A3029),
    dangerInk: Color(0xFFF2A190),
    toastBg: Color(0xFF46423A),
    toastInk: Color(0xFFF3EBD3),
    mark: Color(0xFFB39845),
    scrim: Color(0x6B000000), // 42%
    grabber: Color(0xFF4A463E),
  );

  // Token gak pernah diubah per widget; set baru = konstanta baru.
  @override
  StabiloColors copyWith() => this;

  // ponytail: ganti tema langsung lompat di tengah animasi, bukan blend
  // per warna. Lerp tiap field kalau transisi terang/gelap keliatan kasar.
  @override
  StabiloColors lerp(StabiloColors? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

extension StabiloContext on BuildContext {
  StabiloColors get stabilo => Theme.of(this).extension<StabiloColors>()!;
}

ThemeData stabiloTheme(Brightness brightness) {
  final c = brightness == Brightness.light
      ? StabiloColors.light
      : StabiloColors.dark;
  return ThemeData(
    brightness: brightness,
    fontFamily: StabiloType.ui,
    textTheme: StabiloType.textTheme.apply(
      bodyColor: c.ink,
      displayColor: c.ink,
    ),
    scaffoldBackgroundColor: c.canvas,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.accent,
      brightness: brightness,
      surface: c.canvas,
      onSurface: c.ink,
      onSurfaceVariant: c.ink2,
      primary: c.accent,
      onPrimary: c.onAccent,
      secondary: c.pink,
      error: c.danger,
      onError: c.onDanger,
      outline: c.outline,
      scrim: c.scrim,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.sheet,
      modalBackgroundColor: c.sheet,
      modalBarrierColor: c.scrim,
      dragHandleColor: c.grabber,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.sheet,
      barrierColor: c.scrim,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      titleTextStyle: StabiloType.titleMd.copyWith(color: c.ink),
      contentTextStyle: StabiloType.body.copyWith(color: c.ink2),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.toastBg,
      contentTextStyle: StabiloType.label.copyWith(color: c.toastInk),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: const StadiumBorder(),
    ),
    extensions: [c],
  );
}
