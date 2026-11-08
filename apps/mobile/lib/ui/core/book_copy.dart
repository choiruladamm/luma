import '../../l10n/app_localizations.dart';
import '../../domain/models/book.dart';
import '../../domain/models/markdown_shelf.dart';

extension ShelfBookCopy on ShelfBook {
  String progressLabel(AppLocalizations l10n) {
    if (!opened) return l10n.notStarted;
    if (finished) return l10n.finishedReading;
    return l10n.chapterPosition(chapter, chapterCount);
  }
}

extension ShelfSortCopy on ShelfSort {
  String label(AppLocalizations l10n) => switch (this) {
    ShelfSort.lastOpened => l10n.sortLastOpened,
    ShelfSort.title => l10n.sortTitle,
    ShelfSort.added => l10n.sortAdded,
  };
}

String localizedChapterRanges(
  List<int> chapters,
  AppLocalizations l10n, {
  bool lower = false,
}) {
  if (chapters.isEmpty) return l10n.noChapters;
  final range = chapterRanges(chapters, prefix: '').trim();
  return lower ? l10n.chapterListLower(range) : l10n.chapterList(range);
}

extension MarkdownShelfCopy on MarkdownShelf {
  String label(AppLocalizations l10n) => localizedChapterRanges(chapters, l10n);
  String semanticLabel(String title, AppLocalizations l10n) {
    final parts = [title, l10n.chapterCount(count)];
    final read = chapters
        .where((n) => current != null && n < current!)
        .toList();
    if (read.isNotEmpty) {
      parts.add(
        l10n.chaptersRead(localizedChapterRanges(read, l10n, lower: true)),
      );
    }
    if (chapters.contains(current)) parts.add(l10n.chapterReading(current!));
    return parts.join(', ');
  }
}

/// Nomor bab jadi teks: 3 nomor berurutan atau lebih diringkas jadi rentang.
/// [1, 3, 7] → "Bab 1, 3, 7"; [1, 2] → "Bab 1, 2"; 1..40 → "Bab 1–40".
String chapterRanges(
  List<int> chapters, {
  String prefix = 'Bab',
  String empty = 'Belum ada bab',
}) {
  if (chapters.isEmpty) return empty;
  final parts = <String>[];
  var i = 0;
  while (i < chapters.length) {
    var j = i;
    while (j + 1 < chapters.length && chapters[j + 1] == chapters[j] + 1) {
      j++;
    }
    if (j - i >= 2) {
      parts.add('${chapters[i]}–${chapters[j]}');
    } else {
      for (var k = i; k <= j; k++) {
        parts.add('${chapters[k]}');
      }
    }
    i = j + 1;
  }
  return '$prefix ${parts.join(', ')}';
}
