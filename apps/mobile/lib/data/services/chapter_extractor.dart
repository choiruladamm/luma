import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../../domain/grouping.dart';
import '../../domain/models/book.dart';
import 'epub_parser.dart';

/// Changing this parsing and grouping version requires re-importing books and
/// deleting their `ai_results` because paragraph and group indices can shift
/// (docs/data-model.md).
const parserVersion = 1;

class ParsedChapter {
  const ParsedChapter({
    required this.title,
    required this.paragraphs,
    required this.groups,
    required this.charOffset,
    this.section,
  });

  final String title;

  /// The parent TOC label (see [ChapterSource.section]).
  final String? section;
  final List<RawParagraph> paragraphs;

  /// The `groupIndex` for each paragraph, from [assignGroups].
  final List<int?> groups;

  /// The character count before this chapter, used for reading progress.
  final int charOffset;

  int get charCount => paragraphs.fold(0, (n, p) => n + p.text.length);
}

/// Extracts paragraphs and groups from chapters in [outline] (docs/grouping.md,
/// docs/architecture.md).
///
/// Non-content chapters are identified by structure, not title: link-heavy
/// chapters and chapters without paragraphs are skipped (docs/import-formats.md).
/// [onChapter] reports progress at the start of each source chapter and at the end.
({List<ParsedChapter> chapters, int totalChars}) extractChapters(
  EpubOutline outline, {
  void Function(int done, int total)? onChapter,
}) {
  final docs = <String, Element>{};
  Element body(String file) => docs[file] ??=
      html.parse(_openSelfClosing(outline.html[file] ?? '')).body ??
      Element.tag('body');

  final chapters = <ParsedChapter>[];
  var offset = 0;
  final total = outline.chapters.length;
  for (final (n, source) in outline.chapters.indexed) {
    onChapter?.call(n, total);
    final x = _Extractor(source.startAnchor, source.endAnchor);
    for (final (i, file) in source.files.indexed) {
      x.file(body(file), first: i == 0, last: i == source.files.length - 1);
      if (x.done) break;
    }

    final paragraphs = _tidy(x.blocks);
    final isContent = paragraphs.any((p) => p.type == ParagraphType.paragraph);
    if (!isContent || x.linkChars > x.textChars * 0.6) continue;

    final chapter = ParsedChapter(
      title: _title(source.title, paragraphs),
      section: source.section,
      paragraphs: paragraphs,
      groups: assignGroups(paragraphs),
      charOffset: offset,
    );
    chapters.add(chapter);
    offset += chapter.charCount;
  }
  onChapter?.call(total, total);
  return (chapters: chapters, totalChars: offset);
}

const _blockTags = {
  'p', 'div', 'section', 'article', 'header', 'footer', 'aside', 'main', //
  'blockquote', 'pre', 'li', 'ul', 'ol', 'dl', 'dt', 'dd', 'body',
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
};
const _headingTags = {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};

// ponytail: all tables are skipped; extract cells if a book contains content in tables.
const _skipTags = {
  'script', 'style', 'head', 'title', 'nav', 'img', 'svg', 'figure', //
  'figcaption', 'table', 'math',
};
const _skipClasses = {
  'caption',
  'figcenter',
  'pagenum',
  'x-ebookmaker-pageno',
  'pg-boilerplate',
};
const _voidTags = {
  'br',
  'hr',
  'img',
  'meta',
  'link',
  'input',
  'col',
  'area',
  'base',
  'wbr',
};

final _selfClosing = RegExp(r'<([a-zA-Z][\w:-]*)(\s[^<>]*?)?/>');
final _footnoteMark = RegExp(
  r'^\s*(\[\w{1,4}\]|\(\d{1,3}\)|\d{1,3}|[*†‡§]{1,3})\s*$',
);
final _sceneBreak = RegExp(r'^[\s*⁂•·~]+$');

/// Handles self-closing XHTML anchors, which the HTML5 parser treats as unclosed.
String _openSelfClosing(String xhtml) => xhtml.replaceAllMapped(
  _selfClosing,
  (m) => _voidTags.contains(m[1]!.toLowerCase())
      ? m[0]!
      : '<${m[1]}${m[2] ?? ''}></${m[1]}>',
);

class _Extractor {
  _Extractor(this.start, this.end) : recording = start == null;

  final String? start;
  final String? end;

  bool recording;
  bool done = false;
  bool _sawStart = false;
  final blocks = <RawParagraph>[];

  final _buf = StringBuffer();
  bool _bufHeading = false;
  int _heading = 0;
  int _link = 0;
  int textChars = 0;
  int linkChars = 0;

  void file(Element body, {required bool first, required bool last}) {
    if (!first) recording = true;
    _walk(body, last: last);
    _flush();
    // Fall back to the file start when the anchor is missing to avoid an empty chapter.
    if (first && start != null && !_sawStart && !done) {
      blocks.clear();
      recording = true;
      _walk(body, last: last);
      _flush();
    }
  }

  void _walk(Node node, {required bool last}) {
    for (final child in node.nodes) {
      if (done) return;
      if (child is Text) {
        if (!recording) continue;
        // Source newlines are whitespace; actual line breaks come from <br>.
        _buf.write(child.text.replaceAll(RegExp(r'\s+'), ' '));
        if (_heading > 0) _bufHeading = true;
        final n = child.text.trim().length;
        textChars += n;
        if (_link > 0) linkChars += n;
        continue;
      }
      if (child is! Element) continue;

      final id = child.id.isNotEmpty ? child.id : child.attributes['name'];
      if (id != null && id == start && !_sawStart) {
        _sawStart = true;
        recording = true;
        _buf.clear();
        _bufHeading = false;
      }
      if (last && id != null && id == end) {
        _flush();
        done = true;
        return;
      }
      if (_skip(child)) {
        // Anchors can occur in skipped content, such as footer#pg-footer.
        if (start != null && !_sawStart && _has(child, start!)) {
          _sawStart = true;
          recording = true;
          _buf.clear();
          _bufHeading = false;
        }
        if (last && end != null && _has(child, end!)) {
          _flush();
          done = true;
          return;
        }
        continue;
      }

      final tag = child.localName ?? '';
      if (tag == 'br') {
        if (recording) _buf.write('\n');
        continue;
      }
      if (tag == 'hr') {
        _flush();
        if (recording) {
          blocks.add((type: ParagraphType.sceneBreak, text: '***'));
        }
        continue;
      }

      final block = _blockTags.contains(tag);
      final heading = _headingTags.contains(tag);
      final link = tag == 'a' && child.attributes.containsKey('href');
      if (block) _flush();
      if (heading) _heading++;
      if (link) _link++;
      _walk(child, last: last);
      if (link) _link--;
      if (heading) _heading--;
      if (block) _flush();
    }
  }

  void _flush() {
    final text = _buf.toString();
    _buf.clear();
    final heading = _bufHeading;
    _bufHeading = false;
    if (!recording || text.trim().isEmpty) return;
    blocks.add((
      type: heading ? ParagraphType.heading : ParagraphType.paragraph,
      text: text,
    ));
  }

  static bool _has(Element e, String id) =>
      e.querySelector('[id="$id"], [name="$id"]') != null;

  static bool _skip(Element e) {
    final tag = e.localName ?? '';
    if (_skipTags.contains(tag)) return true;
    if (e.id == 'pg-header' || e.id == 'pg-footer') return true;
    if (e.classes.any(_skipClasses.contains)) return true;
    final type = e.attributes['epub:type'] ?? '';
    if (type.contains('noteref') || type.contains('pagebreak')) return true;
    // Footnote markers include [1], (2), *, †, and <sup>3</sup>.
    if ((tag == 'a' || tag == 'sup') && _footnoteMark.hasMatch(e.text)) {
      return tag == 'sup' || e.attributes.containsKey('href');
    }
    return false;
  }
}

/// Normalizes whitespace and scene breaks while preserving <br> line breaks.
List<RawParagraph> _tidy(List<RawParagraph> blocks) {
  final out = <RawParagraph>[];
  for (final b in blocks) {
    final text = b.text
        .replaceAll(' ', ' ')
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((l) => l.isNotEmpty)
        .join('\n');
    if (text.isEmpty) continue;
    final type = b.type == ParagraphType.paragraph && _sceneBreak.hasMatch(text)
        ? ParagraphType.sceneBreak
        : b.type;
    if (type == ParagraphType.sceneBreak &&
        (out.isEmpty || out.last.type == ParagraphType.sceneBreak)) {
      continue;
    }
    out.add((
      type: type,
      text: type == ParagraphType.sceneBreak ? '***' : text,
    ));
  }
  while (out.isNotEmpty && out.last.type == ParagraphType.sceneBreak) {
    out.removeLast();
  }
  return out;
}

/// Returns a TOC title without footnote markers.
/// Uses the chapter heading when unrelated text precedes it, but preserves
/// more complete TOC labels that begin with the heading.
String _title(String toc, List<RawParagraph> paragraphs) {
  String clean(String s) => s
      .replaceAll(RegExp(r'\[\w{1,4}\]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final title = clean(toc);
  final heading = paragraphs
      .take(3)
      .where((p) => p.type == ParagraphType.heading)
      .map((p) => clean(p.text))
      .firstOrNull;
  if (heading != null &&
      heading.isNotEmpty &&
      heading.length < title.length &&
      title.toLowerCase().contains(heading.toLowerCase()) &&
      !title.toLowerCase().startsWith(heading.toLowerCase())) {
    return heading;
  }
  return title.isEmpty ? toc : title;
}
