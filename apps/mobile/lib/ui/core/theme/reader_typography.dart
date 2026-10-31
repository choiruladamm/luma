import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../domain/models/reader_prefs.dart';
import 'stabilo_type.dart';

/// Font bacaan buat [ReadingFont]. Bawaan sistem = SF di iOS, Roboto di
/// Android ('CupertinoSystemText' cuma ada di iOS; null gak ngosongin family).
String readingFamily(ReadingFont font) => switch (font) {
  ReadingFont.clear => StabiloType.readingFont,
  ReadingFont.book => StabiloType.bookFont,
  ReadingFont.system =>
    defaultTargetPlatform == TargetPlatform.iOS
        ? 'CupertinoSystemText'
        : 'Roboto',
};

/// Tipografi teks bacaan dari pengaturan Aa (font, ukuran, jarak baris,
/// margin). Satu sumber buat halaman baca dan isi sheet Artinya, jadi
/// keduanya selalu sama.
@immutable
class ReaderTypography {
  ReaderTypography(ReaderPrefs prefs, Brightness brightness)
    : this._(
        StabiloType.forBrightness(
          StabiloType.reading.copyWith(
            fontFamily: readingFamily(prefs.font),
            fontSize: prefs.fontSize,
            height: prefs.lineHeight,
          ),
          brightness,
        ),
        prefs.marginWidth,
      );

  const ReaderTypography._(this.style, this.margin);

  /// Tanpa warna: pemakai nambahin `ink` / `onHighlight` sendiri.
  final TextStyle style;

  /// Margin kiri-kanan teks.
  final double margin;

  /// Jarak antar paragraf: 1em ukuran Aa, sama kayak halaman baca.
  double get paragraphGap => style.fontSize!;

  /// Tambahan margin di atas padding dasar layar ([base]); Lega (32) nambah 8,
  /// Sempit sama kayak Pas.
  double inset(double base) => math.max(0.0, margin - base);

  /// Tinggi satu baris teks.
  double get lineExtent => style.fontSize! * style.height!;

  @override
  bool operator ==(Object other) =>
      other is ReaderTypography &&
      other.style == style &&
      other.margin == margin;

  @override
  int get hashCode => Object.hash(style, margin);
}
