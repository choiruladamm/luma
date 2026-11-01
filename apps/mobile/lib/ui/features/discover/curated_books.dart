import '../../../data/services/gutenberg_source.dart';
import '../../../domain/catalog/catalog_row.dart';
import '../../../domain/models/catalog.dart';

/// Buku kurasi buat rak kosong (board 02 / 17): kalimat pembuka + artinya
/// di-hardcode (docs/discover.md, Board). Buku lain pakai Pride and Prejudice.
class CuratedBook {
  const CuratedBook({
    required this.book,
    required this.quote,
    required this.meaning,
  });

  final CatalogBook book;
  final String quote;
  final String meaning;
}

CatalogBook _gutenberg(int id, String title, CatalogAuthor author) =>
    CatalogBook(
      sourceId: 'gutenberg',
      externalId: '$id',
      title: title,
      authors: [author],
      coverUrl: GutenbergSource.coverUrl(id),
      downloadUrl: GutenbergSource.epubUrl(id),
    );

final curatedBooks = [
  CuratedBook(
    book: _gutenberg(
      1342,
      'Pride and Prejudice',
      const CatalogAuthor('Austen, Jane', birth: 1775, death: 1817),
    ),
    quote:
        'It is a truth universally acknowledged, that a single man in '
        'possession of a good fortune, must be in want of a wife.',
    meaning: 'Udah jadi rahasia umum: cowok tajir pasti lagi nyari istri.',
  ),
  CuratedBook(
    book: _gutenberg(
      158,
      'Emma',
      const CatalogAuthor('Austen, Jane', birth: 1775, death: 1817),
    ),
    quote:
        'Emma Woodhouse, handsome, clever, and rich, with a comfortable home '
        'and happy disposition…',
    meaning: 'Emma itu cakep, pinter, tajir, hidupnya enak banget.',
  ),
  CuratedBook(
    book: _gutenberg(
      11,
      "Alice's Adventures in Wonderland",
      const CatalogAuthor('Carroll, Lewis', birth: 1832, death: 1898),
    ),
    quote:
        'Alice was beginning to get very tired of sitting by her sister on '
        'the bank, and of having nothing to do…',
    meaning:
        'Alice bosen banget duduk nemenin kakaknya di pinggir sungai, gak ada '
        'kerjaan.',
  ),
];

/// Kutipan buat buku yang lagi diunduh; bukan kurasi = Pride and Prejudice.
CuratedBook curatedFor(CatalogBook book) => curatedBooks.firstWhere(
  (c) =>
      c.book.sourceId == book.sourceId && c.book.externalId == book.externalId,
  orElse: () => curatedBooks.first,
);
