import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/catalog.dart';
import '../repositories/catalog_repository.dart';
import 'gutenberg_source.dart';

/// Represents one public-domain book source (docs/discover.md).
///
/// Each source has an adapter in `data/services/`, registered through
/// [bookSourcesProvider].
abstract interface class BookSource {
  /// Stable source key such as 'gutenberg' or 'standard_ebooks'; stored in `books.sourceId`.
  String get id;

  /// Display label shown in the UI.
  String get name;

  /// Returns popular books for an empty [query], search results otherwise.
  Future<CatalogPage> search(String query, {int page = 1});

  Future<CatalogBookDetail> fetchDetail(String externalId);

  /// Returns the EPUB bytes for `ImportRepository.importEpub`.
  ///
  /// [isCancelled] is checked on every chunk; cancelling throws.
  Future<Uint8List> download(
    CatalogBook book, {
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  });
}

/// Registry of sources; adding one takes an adapter file plus one line here.
final bookSourcesProvider = Provider<List<BookSource>>(
  (ref) => [GutenbergSource(ref.watch(catalogRepositoryProvider))],
);
