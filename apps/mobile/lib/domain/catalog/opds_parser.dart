import 'package:xml/xml.dart';

import '../models/catalog.dart';

/// Entri buku di feed OPDS Gutenberg (populer). Entri navigasi (Subjects,
/// Authors, ...) gak punya id `/ebooks/{n}.opds`, jadi dibuang.
typedef OpdsEntry = ({int id, String title, String? author});
typedef OpdsFeed = ({List<OpdsEntry> entries, bool hasMore});

final _bookId = RegExp(r'/ebooks/(\d+)\.opds$');
final _wikipedia = RegExp(r'https?://\S*wikipedia\.org/\S+');
final _spaces = RegExp(r'\s+');
const _autoSummaryNote = '(This is an automatically generated summary.)';

/// Feed `/ebooks/search.opds/`: id + judul + penulis (dari `content`, bentuk
/// tampil "Jane Austen"; `content` "N downloads" = gak ada penulis).
OpdsFeed parseOpdsFeed(String xml) {
  final feed = XmlDocument.parse(xml).rootElement;
  final hasMore = feed
      .findElements('link')
      .any((l) => l.getAttribute('rel') == 'next');
  final entries = <OpdsEntry>[];
  for (final entry in feed.findElements('entry')) {
    final id = int.tryParse(
      _bookId.firstMatch(entry.getElement('id')?.innerText ?? '')?.group(1) ??
          '',
    );
    if (id == null) continue;
    final content = _text(entry.getElement('content'));
    entries.add((
      id: id,
      title: _text(entry.getElement('title')),
      author: content.isEmpty || content.endsWith(' downloads')
          ? null
          : content,
    ));
  }
  return (entries: entries, hasMore: hasMore);
}

/// Feed per buku `/ebooks/{id}.opds` → detail. Sinopsis dari paragraf
/// `Summary:` di `content` (gak semua buku punya), link Wikipedia dari
/// paragraf `Note:`, subjek dari `category` LCSH, bookshelves dari link
/// `related` `/ebooks/bookshelf/`, ukuran dari `length` link EPUB noimages.
CatalogBookDetail parseOpdsBook(String xml) {
  final entry = XmlDocument.parse(xml).rootElement.findElements('entry').first;
  String? summary, wikipediaUrl;
  for (final p in entry.findAllElements('p')) {
    final text = _text(p);
    if (text.startsWith('Summary:')) {
      summary = text
          .substring('Summary:'.length)
          .replaceAll(_autoSummaryNote, '')
          .trim();
    } else if (text.startsWith('Note:') && text.contains('Wikipedia')) {
      wikipediaUrl = _wikipedia.firstMatch(text)?.group(0);
    }
  }
  final links = entry.findElements('link');
  final epub = links
      .where((l) => (l.getAttribute('href') ?? '').endsWith('.epub.noimages'))
      .firstOrNull;
  return CatalogBookDetail(
    summary: summary,
    subjects: [
      for (final c in entry.findElements('category'))
        if (c.getAttribute('scheme') == 'http://purl.org/dc/terms/LCSH')
          c.getAttribute('term')!,
    ],
    bookshelves: [
      for (final l in links)
        if (l.getAttribute('rel') == 'related' &&
            (l.getAttribute('href') ?? '').contains('/ebooks/bookshelf/'))
          _shelfName(l.getAttribute('title') ?? ''),
    ],
    fileSize: int.tryParse(epub?.getAttribute('length') ?? ''),
    issued: entry.getElement('published')?.innerText.trim(),
    wikipediaUrl: wikipediaUrl,
  );
}

/// "In Harvard Classics…" → "Harvard Classics".
String _shelfName(String title) {
  var s = title.trim();
  if (s.startsWith('In ')) s = s.substring(3);
  if (s.endsWith('…')) s = s.substring(0, s.length - 1);
  return s;
}

String _text(XmlElement? e) =>
    e == null ? '' : e.innerText.replaceAll(_spaces, ' ').trim();
