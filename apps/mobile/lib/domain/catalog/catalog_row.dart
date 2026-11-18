import 'package:freezed_annotation/freezed_annotation.dart';

part 'catalog_row.freezed.dart';
part 'catalog_row.g.dart';

/// One book from the Project Gutenberg `pg_catalog.csv` dump (docs/discover.md,
/// Local catalog and search). Plain data: safe to return from `Isolate.run`.
@freezed
abstract class CatalogRow with _$CatalogRow {
  const CatalogRow._();

  const factory CatalogRow({
    /// Gutenberg `Text#`; the EPUB and cover URLs are built from it.
    required int id,
    required String title,
    required List<CatalogAuthor> authors,
    @Default([]) List<String> subjects,
    @Default([]) List<String> bookshelves,

    /// Gutenberg release date, `YYYY-MM-DD`. Null when empty.
    String? issued,
  }) = _CatalogRow;

  /// Author names separated by `; `, for LIKE + display.
  String get authorsText => authors.map((a) => a.name).join('; ');
}

/// `Austen, Jane, 1775-1817` → name `Austen, Jane`, 1775, 1817. Either year may be
/// empty (`1900-`, `-1468`), or both.
@freezed
abstract class CatalogAuthor with _$CatalogAuthor {
  const factory CatalogAuthor(String name, {int? birth, int? death}) =
      _CatalogAuthor;

  factory CatalogAuthor.fromJson(Map<String, Object?> json) =>
      _$CatalogAuthorFromJson(json);
}
