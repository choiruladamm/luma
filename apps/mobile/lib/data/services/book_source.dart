import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/catalog.dart';

/// Satu sumber buku public domain (docs/discover.md). Adapter per sumber di
/// `data/services/`, didaftarin lewat [bookSourcesProvider].
abstract interface class BookSource {
  /// 'gutenberg', 'standard_ebooks', ... Disimpen di `books.sourceId`.
  String get id;

  /// Label UI.
  String get name;

  /// query '' = daftar populer, selain itu hasil cari.
  Future<CatalogPage> search(String query, {int page = 1});

  Future<CatalogBookDetail> fetchDetail(String externalId);

  /// Bytes EPUB buat `ImportRepository.importEpub`. [isCancelled] dicek di
  /// tiap chunk; batal = lempar.
  Future<Uint8List> download(
    CatalogBook book, {
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  });
}

/// Registry sumber. Nambah sumber = satu file adapter + satu baris di sini.
final bookSourcesProvider = Provider<List<BookSource>>((ref) => const []);
