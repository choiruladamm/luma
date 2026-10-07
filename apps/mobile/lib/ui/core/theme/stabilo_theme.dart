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
    required this.accentBorder,
    required this.onPink,
    required this.pink,
    required this.pinkSoft,
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
    required this.menuLine,
    required this.fieldLine,
    required this.progressFill,
    required this.progressLine,
    required this.progressLineTrack,
    required this.capsuleLine,
    required this.flash,
    required this.scrimSoft,
    required this.segment,
    required this.bannerTile,
    required this.bannerButton,
    required this.onBannerButton,
    required this.continueInk2,
    required this.continueTrack,
  });

  // Permukaan
  final Color canvas, sheet, muted, track, outline;
  // Teks. ink3 khusus disabled.
  final Color ink, ink2, ink3;
  // Aksen. highlight cuma buat grup paragraf yang lagi dibuka di sheet.
  // accentBorder: outline tombol/opsi accent (gelap: sewarna accent).
  final Color accent, onAccent, accentBorder, pink, onPink;
  // Latar banner pink lembut (Artinya kepotong), garisnya [pink].
  final Color pinkSoft;
  final Color highlight, onHighlight;
  // Status & feedback. mark = penanda grup yang udah diterjemahin.
  final Color danger, onDanger, dangerSoft, dangerInk, toastBg, toastInk, mark;
  // Overlay
  final Color scrim, grabber;
  // Garis pemisah di menu/list, garis field input.
  final Color menuLine, fieldLine;
  // Isi progress bar (terang: tinta, gelap: accent).
  final Color progressFill;
  // Halaman baca imersif (board Baca imersif · ReaderCapsule): garis progres
  // 2pt, garis kapsul, kilatan stabilo di grup tersimpan (puncak 60%).
  final Color progressLine, progressLineTrack, capsuleLine, flash;
  // Scrim tipis di belakang sheet Aa (teks tetep keliatan buat preview),
  // pilihan terpilih di segmented control.
  final Color scrimSoft, segment;
  // ReminderBanner (pink): kotak ikon & tombol di atas pink.
  final Color bannerTile, bannerButton, onBannerButton;
  // ContinueCard: teks kedua (bab) & alur progres. Terang di atas accent,
  // gelap di atas muted.
  final Color continueInk2, continueTrack;

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
    accentBorder: Color(0xFF1A1A1A),
    pink: Color(0xFFFFC2D3),
    pinkSoft: Color(0xFFFFE3EB),
    onPink: Color(0xFF1A1A1A),
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
    menuLine: Color(0xFFECE5D2),
    fieldLine: Color(0xFFCFC7B1),
    progressFill: Color(0xFF1A1A1A),
    progressLine: Color(0xFFE6B800),
    progressLineTrack: Color(0x141A1A1A), // 8%
    capsuleLine: Color(0xFF1A1A1A),
    flash: Color(0x9EFFD84D), // 62%
    scrimSoft: Color(0x141A1A1A), // 8%
    segment: Color(0xFFFFFFFF),
    bannerTile: Color(0xB3FFFDF6), // 70%
    bannerButton: Color(0xFFFFFDF6),
    onBannerButton: Color(0xFF1A1A1A),
    continueInk2: Color(0xFF3D3A2A),
    continueTrack: Color(0x241A1A1A), // 14%
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
    accentBorder: Color(0xFFE9C75A),
    pink: Color(0xFFD99BAE),
    pinkSoft: Color(0xFF4B3E3D), // pink 18% di atas sheet
    onPink: Color(0xFF22201C),
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
    menuLine: Color(0xFF3A3732),
    fieldLine: Color(0xFF5A554B),
    progressFill: Color(0xFFE9C75A),
    progressLine: Color(0xFFE9C75A),
    progressLineTrack: Color(0x1ADDD7C8), // 10%
    capsuleLine: Color(0xFF46423A),
    flash: Color(0x57E9C75A), // 34%
    scrimSoft: Color(0x2E000000), // 18%
    segment: Color(0xFF4A463E),
    bannerTile: Color(0x2E22201C), // 18%
    bannerButton: Color(0xFF22201C),
    onBannerButton: Color(0xFFF3EBD3),
    continueInk2: Color(0xFFA19B8E),
    continueTrack: Color(0xFF46423A),
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
    splashFactory: NoSplash.splashFactory,
    popupMenuTheme: PopupMenuThemeData(
      color: c.sheet,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      menuPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.menu),
        side: BorderSide(color: c.menuLine),
      ),
    ),
    dividerTheme: DividerThemeData(color: c.menuLine, space: 1, thickness: 1),
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
        borderRadius: BorderRadius.circular(Radii.dialog),
      ),
      titleTextStyle: StabiloType.titleMd.copyWith(color: c.ink),
      contentTextStyle: StabiloType.body.copyWith(color: c.ink2),
    ),
    extensions: [c],
  );
}
