import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/models/reader_prefs.dart';
import 'package:luma/ui/core/theme/reader_typography.dart';
import 'package:luma/ui/core/theme/stabilo_type.dart';

void main() {
  test('font, size, line spacing and margin come from the Aa prefs', () {
    for (final font in ReadingFont.values) {
      for (final step in [0, ReaderPrefs.defaultSizeStep, 6]) {
        for (final spacing in LineSpacing.values) {
          for (final margin in TextMargin.values) {
            final prefs = ReaderPrefs(
              font: font,
              sizeStep: step,
              spacing: spacing,
              margin: margin,
            );
            final t = ReaderTypography(prefs, Brightness.light);
            expect(t.style.fontFamily, readingFamily(font));
            expect(t.style.fontSize, ReaderPrefs.sizes[step]);
            expect(t.style.height, prefs.lineHeight);
            expect(t.margin, prefs.marginWidth);
            expect(
              t.lineExtent,
              closeTo(prefs.fontSize * prefs.lineHeight, 1e-9),
            );
          }
        }
      }
    }
  });

  test('dark mode adds 0.05 to the line height', () {
    const prefs = ReaderPrefs();
    final light = ReaderTypography(prefs, Brightness.light);
    final dark = ReaderTypography(prefs, Brightness.dark);
    expect(dark.style.height, closeTo(light.style.height! + 0.05, 1e-9));
  });

  test('every font maps to a bundled family', () {
    expect(readingFamily(ReadingFont.clear), StabiloType.readingFont);
    expect(readingFamily(ReadingFont.book), StabiloType.bookFont);
    expect(readingFamily(ReadingFont.system), 'CupertinoSystemText');
  });
}
