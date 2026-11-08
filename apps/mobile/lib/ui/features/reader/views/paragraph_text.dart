import 'package:flutter/material.dart';

import '../../../../domain/models/book.dart';
import '../../../../domain/models/book_chat.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import 'reader_types.dart';

/// Teks satu paragraf: kata hasil Cari kata di-stabilo (yang lagi dibuka
/// penuh + garis, sisanya setengah), atau kutipan sumber obrolan pas ngintip.
/// Tanpa penanda = [Text] biasa.
Text buildParagraphText({
  required ReaderParagraph paragraph,
  required TextStyle style,
  required StabiloColors colors,
  required int chapterId,
  SearchMarks? search,
  ChatSource? sourceVisit,
}) {
  final c = colors;
  final marks = search;
  if (marks != null && paragraph.type != ParagraphType.sceneBreak) {
    final found = marks.query.ranges(paragraph.text);
    if (found.isNotEmpty) {
      final active =
          marks.chapterId == chapterId && marks.paragraph == paragraph.index;
      final spans = <TextSpan>[];
      var end = 0;
      for (final (i, r) in found.indexed) {
        // Kata yang lagi dibuka: stabilo penuh + garis 1,5. Yang lain
        // yang keliatan: stabilo setengah.
        final current = active && i == 0;
        spans.add(TextSpan(text: paragraph.text.substring(end, r.start)));
        spans.add(
          TextSpan(
            text: paragraph.text.substring(r.start, r.end),
            style: TextStyle(
              backgroundColor: current
                  ? c.highlight
                  : c.highlight.withValues(alpha: 0.5),
              color: current ? c.onHighlight : null,
              decoration: current ? TextDecoration.underline : null,
              decorationColor: c.onHighlight,
              decorationThickness: Layout.outline,
            ),
          ),
        );
        end = r.end;
      }
      spans.add(TextSpan(text: paragraph.text.substring(end)));
      return Text.rich(
        TextSpan(children: spans),
        style: style,
        key: ValueKey('search-paragraph-${paragraph.index}'),
      );
    }
  }
  final ranges =
      sourceVisit?.anchors
          .where(
            (a) =>
                a.chapterId == chapterId && a.paragraphIndex == paragraph.index,
          )
          .toList() ??
      [];
  if (ranges.isEmpty) return Text(paragraph.text, style: style);
  ranges.sort((a, b) => a.start.compareTo(b.start));
  final spans = <TextSpan>[];
  var end = 0;
  for (final range in ranges) {
    if (range.start < end ||
        range.end > paragraph.text.length ||
        chatTextHash(paragraph.text) != range.paragraphHash) {
      continue;
    }
    spans.add(TextSpan(text: paragraph.text.substring(end, range.start)));
    spans.add(
      TextSpan(
        text: paragraph.text.substring(range.start, range.end),
        style: TextStyle(backgroundColor: c.highlight, color: c.onHighlight),
      ),
    );
    end = range.end;
  }
  spans.add(TextSpan(text: paragraph.text.substring(end)));
  return Text.rich(
    TextSpan(children: spans),
    style: style,
    key: ValueKey('source-paragraph-${paragraph.index}'),
  );
}
