import 'package:freezed_annotation/freezed_annotation.dart';

import '../catalog/catalog_row.dart';

part 'catalog.freezed.dart';

/// Satu halaman hasil `BookSource.search` (docs/discover.md, Interface).
@freezed
abstract class CatalogPage with _$CatalogPage {
  const factory CatalogPage({
    required List<CatalogBook> items,
    required bool hasMore,

    /// Jumlah total hasil ("7 hasil"). Null = sumbernya gak tau (populer OPDS).
    int? total,
  }) = _CatalogPage;

  static const empty = CatalogPage(items: [], hasMore: false, total: 0);
}

/// Buku di katalog sumber luar. `sourceId + externalId` = identitas lintas
/// sumber, dipakai buat badge "udah di rak" (`books.sourceId/externalId`).
@freezed
abstract class CatalogBook with _$CatalogBook {
  const factory CatalogBook({
    required String sourceId,
    required String externalId,
    required String title,
    required List<CatalogAuthor> authors,
    required String coverUrl,
    required String downloadUrl,
  }) = _CatalogBook;
}

/// Detail dari `BookSource.fetchDetail`. Semua opsional: tiap sumber beda.
@freezed
abstract class CatalogBookDetail with _$CatalogBookDetail {
  const factory CatalogBookDetail({
    String? summary,
    @Default([]) List<String> subjects,
    @Default([]) List<String> bookshelves,

    /// Ukuran EPUB dalam byte.
    int? fileSize,

    /// Tanggal masuk ke sumber (Gutenberg: tanggal rilis digital, bukan
    /// tahun terbit asli). ISO 8601.
    String? issued,
    String? wikipediaUrl,
  }) = _CatalogBookDetail;
}
