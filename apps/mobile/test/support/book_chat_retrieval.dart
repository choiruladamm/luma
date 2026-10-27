// Development-only offline ablations; no gold labels enter indexing/ranking.
import 'dart:math' as math;

import 'book_chat_gold.dart';
import 'book_chat_spike.dart';

typedef SourceRange = ({SourceParagraph paragraph, int start, int end});
typedef RetrievalChunk = ({Passage passage, List<SourceRange> ranges});

List<RetrievalChunk> groupedChunks(
  List<Passage> corpus,
  List<SourceParagraph> paragraphs,
) => [
  for (final p in corpus)
    (
      passage: p,
      ranges: [
        for (final s in paragraphs)
          if (s.book == p.book &&
              s.chapter == p.chapter &&
              s.index >= p.from &&
              s.index <= p.to)
            (paragraph: s, start: 0, end: s.text.length),
      ],
    ),
];

/// UTF-16 offsets match frozen paragraph evidence and Dart substring indices.
List<RetrievalChunk> windowChunks(
  List<SourceParagraph> paragraphs, {
  required int size,
  required int overlap,
}) {
  if (size < 2 || overlap < 0 || overlap >= size) {
    throw ArgumentError('window size/overlap');
  }
  final out = <RetrievalChunk>[];
  for (final p in paragraphs) {
    var start = 0;
    while (start < p.text.length) {
      var end = math.min(start + size, p.text.length);
      // Prefer a word boundary, but still bound a single oversized word.
      if (end < p.text.length) {
        final boundary = p.text.lastIndexOf(RegExp(r'\s'), end);
        if (boundary > start + size ~/ 2) end = boundary;
        if (_lowSurrogate(p.text.codeUnitAt(end))) end--;
      }
      final text = p.text.substring(start, end);
      out.add((
        passage: (
          id: '${p.book}:${p.chapter}:${p.index}:$start-$end',
          book: p.book,
          revision: 1,
          chapter: p.chapter,
          from: p.index,
          to: p.index,
          text: text,
          hash: textHash(text),
        ),
        ranges: [(paragraph: p, start: start, end: end)],
      ));
      if (end == p.text.length) break;
      var next = math.max(start + 1, end - overlap);
      if (_lowSurrogate(p.text.codeUnitAt(next))) next++;
      start = next;
    }
  }
  return out;
}

bool _lowSurrogate(int code) => code >= 0xdc00 && code <= 0xdfff;

/// Remove metadata expansion only when absent from the user's own context.
String cleanRewrite(EvalCase c, String rewrite) {
  final metadata = words(bookMetadata(c.book).values.join(' ')).toSet();
  final context = words(
    [
      c.question,
      for (final h in caseHistory(c)) '${h.question} ${h.answer}',
    ].join(' '),
  ).toSet();
  return RegExp(r'[\p{L}\p{N}]+', unicode: true)
      .allMatches(rewrite)
      .map((m) => m[0]!)
      .where(
        (w) =>
            !metadata.contains(w.toLowerCase()) ||
            context.contains(w.toLowerCase()),
      )
      .join(' ');
}

/// All windows together must cover one complete alternative per required fact.
bool rangesCover(Evidence e, Iterable<SourceRange> ranges) {
  final valid =
      ranges
          .where(
            (r) =>
                r.start >= 0 &&
                r.end > r.start &&
                r.end <= r.paragraph.text.length &&
                coversEvidence(e, r.paragraph, 0, r.paragraph.text.length),
          )
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  var cursor = e.start;
  for (final r in valid) {
    if (r.end <= cursor) continue;
    if (r.start > cursor) return false;
    cursor = r.end;
    if (cursor >= e.end) return true;
  }
  return false;
}

double? rangeRecall(GoldCase gold, Iterable<RetrievalChunk> chunks) {
  if (gold.facts.isEmpty) return null;
  final ranges = chunks.expand((c) => c.ranges).toList();
  return gold.facts
          .where((f) => f.alternatives.any((e) => rangesCover(e, ranges)))
          .length /
      gold.facts.length;
}

// shortcut: selected quote uses the first intersecting window in this fixture;
// support multi-window selected text before reader integration.
/// Selected quote comes from the user's stable paragraph range, never gold.
String? selectedWindow(EvalCase c, List<RetrievalChunk> chunks) {
  if (c.quote == null) return null;
  final selected = c.quote!;
  final delimiter = selected.lastIndexOf(':');
  final indices = selected
      .substring(delimiter + 1)
      .split('-')
      .map(int.parse)
      .toList();
  final prefix = selected.substring(0, delimiter);
  final matches = chunks.where(
    (s) =>
        s.passage.book == c.book &&
        s.passage.revision == 1 &&
        '${s.passage.book}:${s.passage.chapter}' == prefix &&
        s.passage.from <= indices.last &&
        s.passage.to >= indices.first,
  );
  return matches.isEmpty ? null : matches.first.passage.id;
}
