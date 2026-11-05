import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/catalog/opds_parser.dart';

void main() {
  final popular = File('test/fixtures/catalog/opds_popular.xml')
      .readAsStringSync();
  final book = File('test/fixtures/catalog/opds_book_1342.xml')
      .readAsStringSync();

  test('popular feed: 25 book entries in order, next link = hasMore', () {
    final feed = parseOpdsFeed(popular);
    expect(feed.hasMore, isTrue);
    expect(feed.entries, hasLength(25));
    expect(feed.entries.first, (
      id: 1342,
      title: 'Pride and Prejudice',
      author: 'Jane Austen',
    ));
    expect(feed.entries[1].title, 'Frankenstein; or, The modern Prometheus');
    // "89349 downloads" in content = no author.
    final dictionary = feed.entries.singleWhere((e) => e.id == 37683);
    expect(dictionary.author, isNull);
  });

  test('navigation entries and a feed without next are handled', () {
    const xml = '''
<feed xmlns="http://www.w3.org/2005/Atom">
<entry><id>https://www.gutenberg.org/ebooks/subject/1702.opds</id><title>On England</title></entry>
<entry><id>https://www.gutenberg.org/ebooks/98.opds</id><title>A Tale of Two Cities</title><content type="text">Charles Dickens</content></entry>
</feed>''';
    final feed = parseOpdsFeed(xml);
    expect(feed.hasMore, isFalse);
    expect(feed.entries.single.id, 98);
  });

  test('book feed: summary, wikipedia, subjects, shelves, size, issued', () {
    final detail = parseOpdsBook(book);
    expect(detail.summary, startsWith('"Pride and Prejudice" by Jane Austen'));
    expect(detail.summary, endsWith('character and love.'));
    expect(detail.summary, isNot(contains('automatically generated')));
    expect(
      detail.wikipediaUrl,
      'https://en.wikipedia.org/wiki/Pride_and_Prejudice',
    );
    expect(detail.subjects, hasLength(7));
    expect(detail.subjects.first, 'England -- Fiction');
    expect(detail.bookshelves, [
      'Best Books Ever Listings',
      'Harvard Classics',
      'Category: Romance',
      'Category: Novels',
      'Category: Classics of Literature',
      'Category: British Literature',
    ]);
    expect(detail.fileSize, 609138);
    expect(detail.issued, '1998-06-01T00:00:00+00:00');
  });

  test('book feed without summary or epub leaves fields null', () {
    const xml = '''
<feed xmlns="http://www.w3.org/2005/Atom">
<entry><title>X</title><content type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml"><p>Author: Nobody</p></div></content></entry>
</feed>''';
    final detail = parseOpdsBook(xml);
    expect(detail.summary, isNull);
    expect(detail.wikipediaUrl, isNull);
    expect(detail.fileSize, isNull);
    expect(detail.issued, isNull);
    expect(detail.subjects, isEmpty);
    expect(detail.bookshelves, isEmpty);
  });
}
