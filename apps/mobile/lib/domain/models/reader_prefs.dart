/// Font bacaan di Aa: Jelas (Atkinson), Kayak buku (Literata), Bawaan sistem.
enum ReadingFont { clear, book, system }

enum LineSpacing { tight, normal, loose }

enum TextMargin { narrow, normal, wide }

/// Tema app: Terang / Gelap / Ikut sistem.
enum AppTheme { light, dark, system }

/// Setelan bacaan dari sheet Aa (board 07 Atur bacaan, 02 Tipografi). Disimpen
/// di tabel `settings` biar ikut backup; per perangkat, bukan per buku.
class ReaderPrefs {
  const ReaderPrefs({
    this.sizeStep = defaultSizeStep,
    this.font = ReadingFont.clear,
    this.spacing = LineSpacing.normal,
    this.margin = TextMargin.normal,
    this.theme = AppTheme.system,
    this.hideStatusBar = true,
    this.showProgressLine = true,
  });

  /// 7 step ukuran huruf, default 18,5.
  static const sizes = [16.0, 17.0, 18.0, 18.5, 20.0, 22.0, 24.0];
  static const defaultSizeStep = 3;

  /// Indeks ke [sizes].
  final int sizeStep;
  final ReadingFont font;
  final LineSpacing spacing;
  final TextMargin margin;
  final AppTheme theme;

  /// Status bar ngumpet bareng kapsul baca.
  final bool hideStatusBar;

  /// Garis progres 2pt di bawah layar baca.
  final bool showProgressLine;

  double get fontSize => sizes[sizeStep];

  /// Jarak baris mode terang; gelap +0,05 (lihat `StabiloType.forBrightness`).
  /// Literata butuh +0,05 lagi (board: 1,7 di "Pas").
  double get lineHeight =>
      switch (spacing) {
        LineSpacing.tight => 1.5,
        LineSpacing.normal => 1.65,
        LineSpacing.loose => 1.85,
      } +
      (font == ReadingFont.book ? 0.05 : 0);

  /// Margin kiri-kanan teks bacaan.
  double get marginWidth => switch (margin) {
    TextMargin.narrow => 16,
    TextMargin.normal => 24,
    TextMargin.wide => 32,
  };

  ReaderPrefs copyWith({
    int? sizeStep,
    ReadingFont? font,
    LineSpacing? spacing,
    TextMargin? margin,
    AppTheme? theme,
    bool? hideStatusBar,
    bool? showProgressLine,
  }) => ReaderPrefs(
    sizeStep: (sizeStep ?? this.sizeStep).clamp(0, sizes.length - 1),
    font: font ?? this.font,
    spacing: spacing ?? this.spacing,
    margin: margin ?? this.margin,
    theme: theme ?? this.theme,
    hideStatusBar: hideStatusBar ?? this.hideStatusBar,
    showProgressLine: showProgressLine ?? this.showProgressLine,
  );

  // Kunci di tabel settings. Nilai enum disimpen pake namanya.
  static const _size = 'reader.size';
  static const _font = 'reader.font';
  static const _spacing = 'reader.spacing';
  static const _margin = 'reader.margin';
  static const _theme = 'theme';
  static const _hideStatusBar = 'reader.hideStatusBar';
  static const _showProgressLine = 'reader.showProgressLine';

  Map<String, String> toSettings() => {
    _size: '$sizeStep',
    _font: font.name,
    _spacing: spacing.name,
    _margin: margin.name,
    _theme: theme.name,
    _hideStatusBar: '$hideStatusBar',
    _showProgressLine: '$showProgressLine',
  };

  /// Nilai yang gak dikenal (backup lama/rusak) balik ke default.
  factory ReaderPrefs.fromSettings(Map<String, String> s) {
    T pick<T extends Enum>(List<T> values, String key, T fallback) =>
        values.where((v) => v.name == s[key]).firstOrNull ?? fallback;
    bool flag(String key) => s[key] != 'false';
    final step = int.tryParse(s[_size] ?? '') ?? defaultSizeStep;
    return ReaderPrefs(
      sizeStep: step.clamp(0, sizes.length - 1),
      font: pick(ReadingFont.values, _font, ReadingFont.clear),
      spacing: pick(LineSpacing.values, _spacing, LineSpacing.normal),
      margin: pick(TextMargin.values, _margin, TextMargin.normal),
      theme: pick(AppTheme.values, _theme, AppTheme.system),
      hideStatusBar: flag(_hideStatusBar),
      showProgressLine: flag(_showProgressLine),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderPrefs &&
      other.sizeStep == sizeStep &&
      other.font == font &&
      other.spacing == spacing &&
      other.margin == margin &&
      other.theme == theme &&
      other.hideStatusBar == hideStatusBar &&
      other.showProgressLine == showProgressLine;

  @override
  int get hashCode => Object.hash(
    sizeStep,
    font,
    spacing,
    margin,
    theme,
    hideStatusBar,
    showProgressLine,
  );
}
