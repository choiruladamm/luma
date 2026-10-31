import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/catalog/catalog_query.dart';

void main() {
  test('words become prefix terms, AND-ed', () {
    expect(catalogMatchQuery('pride'), '"pride"*');
    expect(catalogMatchQuery('  Jane   austen '), '"Jane"* "austen"*');
  });

  test('FTS syntax from the user is neutralised', () {
    expect(
      catalogMatchQuery('"pride" OR -x NEAR(a b) *'),
      '"pride"* "OR"* "x"* "NEAR"* "a"* "b"*',
    );
    expect(
      catalogMatchQuery("Alice's adventures"),
      '"Alice"* "s"* "adventures"*',
    );
    expect(catalogMatchQuery('100% proof_x'), '"100"* "proof"* "x"*');
  });

  test('accents and non-latin letters are kept as word characters', () {
    expect(catalogMatchQuery('Brontë'), '"Brontë"*');
    expect(catalogMatchQuery('Достоевский'), '"Достоевский"*');
  });

  test('nothing searchable → null', () {
    expect(catalogMatchQuery(''), isNull);
    expect(catalogMatchQuery('   '), isNull);
    expect(catalogMatchQuery('"*-'), isNull);
  });
}
