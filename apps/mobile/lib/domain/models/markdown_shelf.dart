/// One slot in the chapter strip of a Markdown book card (board Import Markdown 49).
enum SlotState {
  /// Read to the end.
  read,

  /// The chapter being read, filled by its fraction.
  reading,

  /// Imported but not opened.
  unread,

  /// This number isn't imported (below the highest imported number).
  missing,
}

/// Chapters of a Markdown book on the shelf: imported numbers + reading position.
/// Chapters below the reading position count as read (there is one reading position per book).
class MarkdownShelf {
  const MarkdownShelf({
    required this.chapters,
    this.current,
    this.fraction = 0,
  });

  /// Slot limit in the strip; beyond this the strip becomes a single bar.
  static const maxSlots = 16;

  /// Imported chapter numbers, ascending.
  final List<int> chapters;

  /// Chapter number of the reading position; null = never opened.
  final int? current;

  /// 0..1 within chapter [current].
  final double fraction;

  /// Number of imported chapters (not the highest number).
  int get count => chapters.length;

  int get highest => chapters.isEmpty ? 0 : chapters.last;

  /// Highest number > [maxSlots]: slots are unreadable, so the strip becomes a single bar.
  bool get collapsed => highest > maxSlots;

  bool _isRead(int n) => current != null && n < current!;

  /// One slot per chapter number, from 1 to [highest].
  List<SlotState> get slots {
    final have = chapters.toSet();
    return [
      for (var n = 1; n <= highest; n++)
        if (!have.contains(n))
          SlotState.missing
        else if (_isRead(n))
          SlotState.read
        else if (n == current)
          SlotState.reading
        else
          SlotState.unread,
    ];
  }

  /// Fill of the fallback bar: chapters read ÷ chapters imported, plus the fraction
  /// of the chapter being read.
  double get barFraction {
    if (chapters.isEmpty || current == null) return 0;
    final read = chapters.where(_isRead).length;
    final reading = chapters.contains(current) ? fraction : 0;
    return ((read + reading) / count).clamp(0, 1).toDouble();
  }
}
