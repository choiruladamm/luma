import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../domain/catalog/catalog_row.dart';
import '../../domain/catalog/opds_parser.dart';
import '../../domain/models/catalog.dart';
import '../repositories/catalog_repository.dart';
import 'book_source.dart';
import 'http_client.dart';

/// Project Gutenberg (docs/discover.md, Adapter Gutenberg): cari dari
/// katalog lokal, populer / detail / download dari OPDS + URL rakitan.
class GutenbergSource implements BookSource {
  GutenbergSource(
    this._catalog, {
    Dio? dio,
    this.retryDelay = const Duration(seconds: 2),
  }) : _dio = dio ?? lumaDio();

  final CatalogRepository _catalog;
  final Dio _dio;
  final Duration retryDelay;

  static const base = 'https://www.gutenberg.org';
  static const downloadTimeout = Duration(seconds: 60);

  /// Konvensi URL gutenberg.org, stabil bertahun-tahun; gak perlu request
  /// per item. `.epub.noimages`: parser kita buang gambar (chapter_extractor).
  static String coverUrl(int id) =>
      '$base/cache/epub/$id/pg$id.cover.medium.jpg';
  static String epubUrl(int id) => '$base/ebooks/$id.epub.noimages';

  @override
  String get id => 'gutenberg';

  @override
  String get name => 'Project Gutenberg';

  @override
  Future<CatalogPage> search(String query, {int page = 1}) async {
    if (query.trim().isEmpty) return _popular(page);
    final rows = await _catalog.search(query, page: page);
    final total = await _catalog.searchCount(query);
    return CatalogPage(
      items: rows.map(_fromRow).toList(),
      hasMore: page * CatalogRepository.pageSize < total,
      total: total,
    );
  }

  /// `sort_order=downloads`, 25/halaman. Penulis diambil dari katalog lokal
  /// kalau ada (bentuk "Austen, Jane" + tahun hidup, konsisten sama hasil
  /// cari); fallback nama tampil dari feed.
  Future<CatalogPage> _popular(int page) async {
    final xml = await _get(
      '$base/ebooks/search.opds/',
      query: {
        'sort_order': 'downloads',
        'start_index': '${(page - 1) * CatalogRepository.pageSize + 1}',
      },
    );
    final feed = parseOpdsFeed(xml);
    final items = <CatalogBook>[];
    for (final entry in feed.entries) {
      final row = await _catalog.byId(entry.id);
      items.add(
        row != null
            ? _fromRow(row)
            : _book(
                entry.id,
                title: entry.title,
                authors: [
                  if (entry.author != null) CatalogAuthor(entry.author!),
                ],
              ),
      );
    }
    return CatalogPage(items: items, hasMore: feed.hasMore);
  }

  @override
  Future<CatalogBookDetail> fetchDetail(String externalId) async =>
      parseOpdsBook(await _get('$base/ebooks/$externalId.opds'));

  /// Batal → `DioException` tipe `cancel`, sama kayak sync katalog.
  @override
  Future<Uint8List> download(
    CatalogBook book, {
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final cancel = CancelToken();
    void checkpoint() {
      if (isCancelled?.call() ?? false) cancel.cancel();
    }

    checkpoint();
    final response = await retryOnBusy(
      delay: retryDelay,
      () => _dio.get<List<int>>(
        book.downloadUrl,
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: downloadTimeout,
        ),
        onReceiveProgress: (received, total) {
          checkpoint();
          onProgress?.call(total > 0 ? received / total : -1);
        },
      ),
    );
    if (isCancelled?.call() ?? false) {
      throw DioException.requestCancelled(
        requestOptions: response.requestOptions,
        reason: 'dibatalin',
      );
    }
    return Uint8List.fromList(response.data!);
  }

  Future<String> _get(String url, {Map<String, String>? query}) async {
    final response = await retryOnBusy(
      delay: retryDelay,
      () => _dio.get<String>(
        url,
        queryParameters: query,
        options: Options(responseType: ResponseType.plain),
      ),
    );
    return response.data!;
  }

  CatalogBook _fromRow(CatalogRow row) =>
      _book(row.id, title: row.title, authors: row.authors);

  CatalogBook _book(
    int id, {
    required String title,
    required List<CatalogAuthor> authors,
  }) => CatalogBook(
    sourceId: this.id,
    externalId: '$id',
    title: title,
    authors: authors,
    coverUrl: coverUrl(id),
    downloadUrl: epubUrl(id),
  );
}
