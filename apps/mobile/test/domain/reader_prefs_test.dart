import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/models/reader_prefs.dart';

void main() {
  test(
    'defaults: 18,5, Jelas, Pas, margin 24, follow iOS, both toggles on',
    () {
      const p = ReaderPrefs();
      expect(p.fontSize, 18.5);
      expect(p.lineHeight, 1.65);
      expect(p.marginWidth, 24);
      expect(p.theme, AppTheme.system);
      expect(p.hideStatusBar, isTrue);
      expect(p.showProgressLine, isTrue);
      expect(ReaderPrefs.fromSettings(const {}), p);
    },
  );

  test('settings round trip', () {
    const p = ReaderPrefs(
      sizeStep: 6,
      font: ReadingFont.book,
      spacing: LineSpacing.loose,
      margin: TextMargin.narrow,
      theme: AppTheme.dark,
      hideStatusBar: false,
      showProgressLine: false,
    );
    expect(ReaderPrefs.fromSettings(p.toSettings()), p);
    expect(p.fontSize, 24);
    expect(p.lineHeight, closeTo(1.9, 1e-9)); // Lega 1,85 + Literata 0,05
    expect(p.marginWidth, 16);
  });

  test('unknown or broken values fall back to defaults', () {
    final p = ReaderPrefs.fromSettings(const {
      'reader.size': '99',
      'reader.font': 'comic-sans',
      'reader.spacing': '',
      'theme': 'neon',
    });
    expect(p.sizeStep, 6); // clamped, not thrown
    expect(p.font, ReadingFont.clear);
    expect(p.spacing, LineSpacing.normal);
    expect(p.theme, AppTheme.system);
  });

  test('size steps stop at both ends', () {
    expect(const ReaderPrefs(sizeStep: 0).copyWith(sizeStep: -1).sizeStep, 0);
    expect(const ReaderPrefs(sizeStep: 6).copyWith(sizeStep: 7).sizeStep, 6);
  });
}
