import 'package:freezed_annotation/freezed_annotation.dart';

part 'catalog_row.freezed.dart';
part 'catalog_row.g.dart';

/// Satu buku dari dump `pg_catalog.csv` Project Gutenberg (docs/discover.md,
/// Katalog lokal). Data polos: aman dikirim balik dari `Isolate.run`.
@freezed
abstract class CatalogRow with _$CatalogRow {
  const CatalogRow._();

  const factory CatalogRow({
    /// `Text#` Gutenberg; URL EPUB & cover dirakit dari sini.
    required int id,
    required String title,
    required List<CatalogAuthor> authors,
    @Default([]) List<String> subjects,
    @Default([]) List<String> bookshelves,

    /// Tanggal rilis di Gutenberg, `YYYY-MM-DD`. Null kalau kosong.
    String? issued,
  }) = _CatalogRow;

  /// Nama penulis dipisah `; `, buat LIKE + tampil.
  String get authorsText => authors.map((a) => a.name).join('; ');
}

/// `Austen, Jane, 1775-1817` → name `Austen, Jane`, 1775, 1817. Tahun bisa
/// kosong salah satu (`1900-`, `-1468`) atau dua-duanya.
@freezed
abstract class CatalogAuthor with _$CatalogAuthor {
  const factory CatalogAuthor(String name, {int? birth, int? death}) =
      _CatalogAuthor;

  factory CatalogAuthor.fromJson(Map<String, Object?> json) =>
      _$CatalogAuthorFromJson(json);
}
