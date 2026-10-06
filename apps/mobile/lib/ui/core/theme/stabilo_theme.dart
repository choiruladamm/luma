import 'package:flutter/material.dart';

import 'stabilo_type.dart';

/// Token warna Stabilo (docs bagian 5).
@immutable
class StabiloColors extends ThemeExtension<StabiloColors> {
  const StabiloColors({
    required this.canvas,
    required this.sheet,
    required this.muted,
    required this.ink,
    required this.ink2,
    required this.accent,
    required this.pink,
  });

  final Color canvas, sheet, muted, ink, ink2, accent, pink;

  static const light = StabiloColors(
    canvas: Color(0xFFFFFBEF),
    sheet: Color(0xFFFFFDF6),
    muted: Color(0xFFF2EDDD),
    ink: Color(0xFF1C1C1C),
    ink2: Color(0xFF5E5A4E),
    accent: Color(0xFFFFD84D),
    pink: Color(0xFFFFC2D3),
  );

  static const dark = StabiloColors(
    canvas: Color(0xFF22201C),
    sheet: Color(0xFF2C2A25),
    muted: Color(0xFF36332D),
    ink: Color(0xFFDDD7C8),
    ink2: Color(0xFFA19B8E),
    accent: Color(0xFFE9C75A),
    pink: Color(0xFFD99BAE),
  );

  @override
  StabiloColors copyWith({
    Color? canvas,
    Color? sheet,
    Color? muted,
    Color? ink,
    Color? ink2,
    Color? accent,
    Color? pink,
  }) => StabiloColors(
    canvas: canvas ?? this.canvas,
    sheet: sheet ?? this.sheet,
    muted: muted ?? this.muted,
    ink: ink ?? this.ink,
    ink2: ink2 ?? this.ink2,
    accent: accent ?? this.accent,
    pink: pink ?? this.pink,
  );

  @override
  StabiloColors lerp(StabiloColors? other, double t) {
    if (other == null) return this;
    return StabiloColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      sheet: Color.lerp(sheet, other.sheet, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      ink2: Color.lerp(ink2, other.ink2, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      pink: Color.lerp(pink, other.pink, t)!,
    );
  }
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
      primary: c.accent,
      onPrimary: const Color(0xFF1C1C1C),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.sheet),
    extensions: [c],
  );
}
