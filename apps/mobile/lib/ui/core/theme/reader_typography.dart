import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../domain/models/reader_prefs.dart';
import 'stabilo_type.dart';

/// Reading font for [ReadingFont]. System default = SF on iOS, Roboto on
/// Android ('CupertinoSystemText' exists only on iOS; null doesn't blank the family).
String readingFamily(ReadingFont font) => switch (font) {
  ReadingFont.clear => StabiloType.readingFont,
  ReadingFont.book => StabiloType.bookFont,
  ReadingFont.system =>
    defaultTargetPlatform == TargetPlatform.iOS
        ? 'CupertinoSystemText'
        : 'Roboto',
};

/// Typography of the reading text from the Aa settings (font, size, line spacing,
/// margin). One source for the reading page and the Artinya sheet body, so the
/// two always match.
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

  /// Has no color: callers add `ink` / `onHighlight` themselves.
  final TextStyle style;

  /// Horizontal margin of the text.
  final double margin;

  /// Gap between paragraphs: 1em of the Aa size, same as the reading page.
  double get paragraphGap => style.fontSize!;

  /// Height of one text line.
  double get lineExtent => style.fontSize! * style.height!;

  @override
  bool operator ==(Object other) =>
      other is ReaderTypography &&
      other.style == style &&
      other.margin == margin;

  @override
  int get hashCode => Object.hash(style, margin);
}
