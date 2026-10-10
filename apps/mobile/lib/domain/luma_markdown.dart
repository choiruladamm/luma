import 'grouping.dart';
import 'models/book.dart';

enum LumaMarkdownError {
  /// Header (frontmatter) ada tapi isinya salah: `book_key` bukan slug,
  /// `chapter` bukan angka.
  badFrontmatter,

  /// Gak ada satu pun paragraf bacaan.
  empty,

  /// Filenya gak kebaca (dipakai pemanggil, bukan parser).
  unreadable,
}

class LumaMarkdownException implements Exception {
  const LumaMarkdownException(this.error, [this.detail, this.value]);

  final LumaMarkdownError error;

  /// Kunci frontmatter yang salah (`book_key`, `chapter`).
  final String? detail;

  /// Isi mentah kunci itu, buat ditampilin ke user.
  final String? value;

  @override
  String toString() => 'LumaMarkdownException($error, $detail)';
}

/// Satu file `.md` = satu chapter (docs/ideas/import-formats.md).
///
/// Field meta diisi dari frontmatter, kalau kosong dari tebakan (heading
/// pertama, nama file). Yang gak bisa ditebak tetap null, diisi UI / importer.
class ParsedMarkdown {
  const ParsedMarkdown({
    required this.paragraphs,
    required this.groups,
    required this.complete,
    this.bookKey,
    this.book,
    this.author,
    this.chapter,
    this.chapterTitle,
  });

  final List<RawParagraph> paragraphs;

  /// `groupIndex` per paragraf, dari [assignGroups].
  final List<int?> groups;

  /// Frontmatter ngasih `book_key` dan `chapter` sendiri: gak perlu nanya
  /// user, langsung import.
  final bool complete;

  final String? bookKey;
  final String? book;
  final String? author;
  final int? chapter;
  final String? chapterTitle;

  int get charCount => paragraphs.fold(0, (n, p) => n + p.text.length);
}

/// Parse isi file Luma Markdown. Frontmatter opsional; body toleran sama
/// Markdown umum supaya hasil konversi PDF (Marker/Docling) langsung kebaca.
///
/// Lempar [LumaMarkdownException] kalau frontmatter salah atau gak ada
/// paragraf bacaan. [fileName] dipakai buat tebakan judul & nomor bab.
ParsedMarkdown parseLumaMarkdown(String source, {String? fileName}) {
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  final (front, bodyStart) = _frontmatter(lines);
  final (paragraphs, h1) = _body(lines.skip(bodyStart));
  if (!paragraphs.any((p) => p.type == ParagraphType.paragraph)) {
    throw const LumaMarkdownException(LumaMarkdownError.empty);
  }

  final name = fileName == null ? null : _fileStem(fileName);
  final book =
      front['book'] ?? h1 ?? (name == null ? null : _bookFromName(name));
  final chapter = _chapter(front['chapter']) ?? _chapterFromName(name);
  final slug = slugify(book ?? '');
  return ParsedMarkdown(
    paragraphs: paragraphs,
    groups: assignGroups(paragraphs),
    complete: front['book_key'] != null && front['chapter'] != null,
    bookKey: front['book_key'] ?? (slug.isEmpty ? null : slug),
    book: book,
    author: front['author'],
    chapter: chapter,
    chapterTitle: front['chapter_title'] ?? _firstHeading(paragraphs),
  );
}

/// Slug huruf kecil + strip buat `book_key`: "Atomic Habits!" → "atomic-habits".
// ponytail: cuma a-z0-9, huruf non-latin kebuang. Tambah transliterasi kalau
// ada judul non-latin yang kepake.
String slugify(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

final _slug = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
final _keyLine = RegExp(r'^([A-Za-z_][\w-]*)\s*:(.*)$');

/// Frontmatter = `---` di baris pertama, `key: value` semua, ditutup `---`.
/// Selain itu dianggap body (`---` di awal file bisa pemisah adegan).
(Map<String, String>, int) _frontmatter(List<String> lines) {
  if (lines.isEmpty || lines.first.trim() != '---') return (const {}, 0);
  final end = lines.indexWhere((l) => l.trim() == '---', 1);
  if (end < 0) return (const {}, 0);

  final map = <String, String>{};
  for (final line in lines.sublist(1, end)) {
    if (line.trim().isEmpty) continue;
    final m = _keyLine.firstMatch(line.trim());
    if (m == null) return (const {}, 0);
    final value = m[2]!.trim().replaceAll(RegExp(r'''^["']|["']$'''), '');
    if (value.isNotEmpty) map[m[1]!] = value;
  }
  if (map.isEmpty) return (const {}, 0);

  final key = map['book_key'];
  if (key != null && !_slug.hasMatch(key)) {
    throw LumaMarkdownException(
      LumaMarkdownError.badFrontmatter,
      'book_key',
      key,
    );
  }
  final chapter = map['chapter'];
  if (chapter != null && int.tryParse(chapter) == null) {
    throw LumaMarkdownException(
      LumaMarkdownError.badFrontmatter,
      'chapter',
      chapter,
    );
  }
  return (map, end + 1);
}

final _heading = RegExp(r'^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$');
final _sceneBreak = RegExp(r'^\s*([*\-_])(\s*\1){2,}\s*$');
final _listItem = RegExp(r'^\s*(?:[-*+]|\d+[.)])\s+');
final _fence = RegExp(r'^\s*(```|~~~)');
final _image = RegExp(r'!\[[^\]]*\]\([^)]*\)');
final _link = RegExp(r'\[([^\]]*)\]\([^)]*\)');
final _bold = RegExp(r'(\*\*|__)(.+?)\1');
final _italic = RegExp(r'\*(.+?)\*|(?<!\w)_(.+?)_(?!\w)');

/// Teks polos: gambar dibuang, link sisa teksnya, penanda tebal/miring/kode
/// dilepas (`paragraphs.text` teks polos, sama kayak EPUB).
String _inline(String s) => s
    .replaceAll(_image, '')
    .replaceAllMapped(_link, (m) => m[1]!)
    .replaceAllMapped(_bold, (m) => m[2]!)
    .replaceAllMapped(_italic, (m) => m[1] ?? m[2]!)
    .replaceAll('`', '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Paragraf + teks `#` (level 1) pertama, buat tebakan judul buku. Level
/// heading gak disimpen di [RawParagraph].
(List<RawParagraph>, String?) _body(Iterable<String> lines) {
  final out = <RawParagraph>[];
  final buf = <String>[];
  String? h1;
  var inFence = false;

  void flush() {
    final text = _inline(buf.join(' '));
    buf.clear();
    if (text.isNotEmpty) out.add((type: ParagraphType.paragraph, text: text));
  }

  for (final raw in lines) {
    if (_fence.hasMatch(raw)) {
      flush();
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;

    final line = raw.trim();
    if (line.isEmpty) {
      flush();
    } else if (_sceneBreak.hasMatch(line)) {
      flush();
      out.add((type: ParagraphType.sceneBreak, text: '***'));
    } else if (_heading.firstMatch(line) case final h?) {
      flush();
      final text = _inline(h[2]!);
      if (text.isEmpty) continue;
      out.add((type: ParagraphType.heading, text: text));
      if (h[1] == '#') h1 ??= text;
    } else if (line.startsWith('|')) {
      flush(); // tabel dibuang
    } else if (_listItem.hasMatch(line)) {
      flush();
      buf.add(line.replaceFirst(_listItem, ''));
    } else {
      buf.add(line.replaceFirst(RegExp(r'^>\s?'), ''));
    }
  }
  flush();
  return (out, h1);
}

String? _firstHeading(List<RawParagraph> paras) {
  for (final p in paras) {
    if (p.type == ParagraphType.heading) return p.text;
  }
  return null;
}

String _fileStem(String fileName) {
  final base = fileName.split(RegExp(r'[\\/]')).last;
  final dot = base.lastIndexOf('.');
  return dot > 0 ? base.substring(0, dot) : base;
}

/// "atomic-habits_bab3" → "Atomic Habits Bab3".
String _titleCase(String stem) => stem
    .split(RegExp(r'[-_\s]+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');

int? _chapter(String? s) => s == null ? null : int.tryParse(s);

// Kata utuh, bukan potongan: "catch-22" bukan bab 22.
final _chapterName = RegExp(
  r'(?<![a-z])(?:bab|chapter|chap|ch)[\s_-]*0*(\d+)',
  caseSensitive: false,
);

/// Judul buku dari nama file tanpa token bab: "bab-1-deep-work" → "Deep Work".
/// Isinya cuma token bab ("bab-3") → nama file utuh.
String _bookFromName(String stem) {
  final rest = _titleCase(stem.replaceFirst(_chapterName, ' '));
  return rest.isEmpty ? _titleCase(stem) : rest;
}

int? _chapterFromName(String? stem) {
  if (stem == null) return null;
  final m = _chapterName.firstMatch(stem);
  return m == null ? null : int.parse(m[1]!);
}
