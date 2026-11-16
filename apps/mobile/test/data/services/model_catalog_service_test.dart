import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/services/model_catalog_service.dart';

CatalogModel model(String id, {String? name, int ctx = 32000, double p = 1}) =>
    CatalogModel.fromJson({
      'id': id,
      'name': ?name,
      'context_length': ctx,
      'pricing': {'prompt': '${p / 1e6}', 'completion': '${p / 1e6}'},
    });

void main() {
  test('fromJson reads prices as strings, label drops the provider', () {
    final m = model('google/gemini', name: 'Google: Gemini 3 Flash', p: 0.1);
    expect(m.label, 'Gemini 3 Flash');
    expect(m.cheap, isTrue);
    expect(m.longContext, isFalse);
    expect(model('x/y').label, 'x/y'); // no name → id
    expect(model('x/y', ctx: 128000).longContext, isTrue);
  });

  test('filterCatalog: search, filter, cheap first then by label', () {
    final all = [
      model('a/zeta', name: 'Zeta', p: 0.1),
      model('a/big', name: 'Big', p: 5, ctx: 200000),
      model('a/alpha', name: 'Alpha', p: 0.2),
    ];
    expect(filterCatalog(all).map((m) => m.label), ['Alpha', 'Zeta', 'Big']);
    expect(
      filterCatalog(all, filter: CatalogFilter.cheap).map((m) => m.label),
      ['Alpha', 'Zeta'],
    );
    expect(
      filterCatalog(all, filter: CatalogFilter.longContext).map((m) => m.id),
      ['a/big'],
    );
    expect(filterCatalog(all, query: ' ZET ').map((m) => m.id), ['a/zeta']);
  });
}
