import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/catalog/catalog_row.dart';
import 'package:luma/domain/catalog/pg_catalog_parser.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

const _header =
    'Text#,Type,Issued,Title,Language,Authors,Subjects,LoCC,Bookshelves\n';

void main() {
  group('parsePgCatalog', () {
    test('keeps English text rows only, skips broken rows', () {
      final rows = parsePgCatalog(
        _bytes(
          '$_header'
          '1,Text,1971-12-01,Declaration,en,"Jefferson, Thomas, 1743-1826",a; b,E201,Politics; Category: Essays\n'
          '2,Sound,2000-01-01,Audio,en,Various,,,\n'
          '3,Text,2000-01-01,Livre,fr,"Hugo, Victor, 1802-1885",,,\n'
          'x,Text,2000-01-01,Bad id,en,,,,\n'
          'short,row\n'
          '\n'
          '4,Text,,No date,en,,,,\n',
        ),
      );
      expect(rows.map((r) => r.id), [1, 4]);
      final first = rows.first;
      expect(first.title, 'Declaration');
      expect(first.issued, '1971-12-01');
      expect(first.authors, [
        const CatalogAuthor('Jefferson, Thomas', birth: 1743, death: 1826),
      ]);
      expect(first.authorsText, 'Jefferson, Thomas');
      expect(first.subjects, ['a', 'b']);
      expect(first.bookshelves, ['Politics', 'Category: Essays']);
      expect(rows.last.issued, isNull);
      expect(rows.last.authors, isEmpty);
    });

    test('quoted title with newline, comma and escaped quote', () {
      final rows = parsePgCatalog(
        _bytes(
          '$_header'
          '2,Text,1972-12-01,"The Bill of Rights\nThe Ten ""Original"" Amendments, annotated",en,United States,,,\r\n'
          '5,Text,1973-01-01,Next,en,,,,',
        ),
      );
      expect(rows.map((r) => r.id), [2, 5]);
      expect(
        rows.first.title,
        'The Bill of Rights\nThe Ten "Original" Amendments, annotated',
      );
      expect(rows.first.authors, [const CatalogAuthor('United States')]);
    });

    test('real dump excerpt: Pride and Prejudice is id 1342', () {
      final rows = parsePgCatalog(
        File('test/fixtures/catalog/pg_catalog_sample.csv').readAsBytesSync(),
      );
      expect(rows.length, 22);
      final pp = rows.singleWhere((r) => r.id == 1342);
      expect(pp.title, 'Pride and Prejudice');
      expect(pp.authors, [
        const CatalogAuthor('Austen, Jane', birth: 1775, death: 1817),
      ]);
      expect(pp.bookshelves, contains('Harvard Classics'));
      expect(pp.subjects, contains('Love stories'));
      // Multiline title in the real file.
      expect(rows.singleWhere((r) => r.id == 2).title, contains('\n'));
      // Translator kept as a person, role tag dropped.
      final quixote = rows.singleWhere((r) => r.id == 996);
      expect(quixote.authors.map((a) => a.name), [
        'Cervantes Saavedra, Miguel de',
        'Ormsby, John',
      ]);
      expect(rows.where((r) => r.id > 99000), isEmpty);
    });
  });

  group('parseAuthors', () {
    test('year shapes', () {
      expect(parseAuthors('Austen, Jane, 1775-1817'), [
        const CatalogAuthor('Austen, Jane', birth: 1775, death: 1817),
      ]);
      expect(parseAuthors('Krol, Ed, 1951-'), [
        const CatalogAuthor('Krol, Ed', birth: 1951),
      ]);
      expect(parseAuthors('Martorell, Joanot, -1468'), [
        const CatalogAuthor('Martorell, Joanot', death: 1468),
      ]);
      expect(parseAuthors('Brown, William Wells, 1814?-1884'), [
        const CatalogAuthor('Brown, William Wells', birth: 1814, death: 1884),
      ]);
      expect(parseAuthors('Various'), [const CatalogAuthor('Various')]);
      expect(parseAuthors('Murray, John'), [
        const CatalogAuthor('Murray, John'),
      ]);
      expect(parseAuthors(''), isEmpty);
    });

    test('name with comma inside, role tags, several people', () {
      expect(
        parseAuthors(
          'Kennedy, John F. (John Fitzgerald), 1917-1963; '
          'Leech, John, 1817-1864 [Illustrator]; Anonymous',
        ),
        [
          const CatalogAuthor(
            'Kennedy, John F. (John Fitzgerald)',
            birth: 1917,
            death: 1963,
          ),
          const CatalogAuthor('Leech, John', birth: 1817, death: 1864),
          const CatalogAuthor('Anonymous'),
        ],
      );
    });

    test('CatalogAuthor json round-trips', () {
      const a = CatalogAuthor('Austen, Jane', birth: 1775, death: 1817);
      expect(CatalogAuthor.fromJson(jsonDecode(jsonEncode(a.toJson()))), a);
      expect(
        CatalogAuthor.fromJson(const {'name': 'Various'}),
        const CatalogAuthor('Various'),
      );
    });
  });

  test('splitList trims and drops empties', () {
    expect(splitList(' a ; ;b;'), ['a', 'b']);
    expect(splitList(''), isEmpty);
  });
}
