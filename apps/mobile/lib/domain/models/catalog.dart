import 'package:freezed_annotation/freezed_annotation.dart';

import '../catalog/catalog_row.dart';

part 'catalog.freezed.dart';

/// One page of `BookSource.search` results (docs/discover.md, Sources and discovery).
@freezed
abstract class CatalogPage with _$CatalogPage {
  const factory CatalogPage({
    required List<CatalogBook> items,
    required bool hasMore,

    /// Total number of results ("7 hasil"). Null = the source doesn't know (OPDS popular).
    int? total,
  }) = _CatalogPage;

  static const empty = CatalogPage(items: [], hasMore: false, total: 0);
}

/// A book in an external source's catalog. `sourceId + externalId` = identity across
/// sources, used for the "already on the shelf" badge (`books.sourceId/externalId`).
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

/// Detail from `BookSource.fetchDetail`. All optional: each source differs.
@freezed
abstract class CatalogBookDetail with _$CatalogBookDetail {
  const factory CatalogBookDetail({
    String? summary,
    @Default([]) List<String> subjects,
    @Default([]) List<String> bookshelves,

    /// EPUB size in bytes.
    int? fileSize,

    /// Date it entered the source (Gutenberg: digital release date, not the original
    /// publication year). ISO 8601.
    String? issued,
    String? wikipediaUrl,
  }) = _CatalogBookDetail;
}
