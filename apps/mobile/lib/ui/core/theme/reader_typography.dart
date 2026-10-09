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
    : style = StabiloType.forBrightness(
        StabiloType.reading.copyWith(
          fontFamily: readingFamily(prefs.font),
          fontSize: prefs.fontSize,
          height: prefs.lineHeight,
        ),
        brightness,
      ),
      margin = prefs.marginWidth;

  /// Tanpa warna: pemakai nambahin `ink` / `onHighlight` sendiri.
  final TextStyle style;

  /// Margin kiri-kanan teks.
  final double margin;

  /// Tinggi satu baris teks.
  double get lineExtent => style.fontSize! * style.height!;
}
