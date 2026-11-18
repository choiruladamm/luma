/// Reading font in Aa: Jelas (Atkinson), Kayak buku (Literata), System default.
enum ReadingFont { clear, book, system }

enum LineSpacing { tight, normal, loose }

enum TextMargin { narrow, normal, wide }

/// App theme: Terang / Gelap / Ikut sistem.
enum AppTheme { light, dark, system }

/// Reading settings from the Aa sheet (board 07 Atur bacaan, 02 Tipografi). Stored
/// in the `settings` table so they are included in backups; per device, not per book.
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

  /// 7 font-size steps, default 18.5.
  static const sizes = [16.0, 17.0, 18.0, 18.5, 20.0, 22.0, 24.0];
  static const defaultSizeStep = 3;

  /// Index into [sizes].
  final int sizeStep;
  final ReadingFont font;
  final LineSpacing spacing;
  final TextMargin margin;
  final AppTheme theme;

  /// The status bar hides together with the reading capsule.
  final bool hideStatusBar;

  /// 2pt progress line at the bottom of the reading screen.
  final bool showProgressLine;

  double get fontSize => sizes[sizeStep];

  /// Line spacing in light mode; dark adds 0.05 (see `StabiloType.forBrightness`).
  /// Literata needs another +0.05 (board: 1.7 at "Pas").
  double get lineHeight =>
      switch (spacing) {
        LineSpacing.tight => 1.5,
        LineSpacing.normal => 1.65,
        LineSpacing.loose => 1.85,
      } +
      (font == ReadingFont.book ? 0.05 : 0);

  /// Left/right margin of the reading text.
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

  // Keys in the settings table. Enum values are stored by name.
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

  /// An unknown value (old/corrupt backup) falls back to the default.
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
