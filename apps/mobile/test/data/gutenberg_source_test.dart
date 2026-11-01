import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart' hide CatalogBook;
import 'package:luma/data/repositories/catalog_repository.dart';
import 'package:luma/data/services/gutenberg_source.dart';
import 'package:luma/data/services/http_client.dart';
import 'package:luma/domain/catalog/catalog_row.dart';
import 'package:luma/domain/catalog/pg_catalog_parser.dart';
import 'package:luma/domain/models/catalog.dart';

import 'catalog_sync_service_test.dart' show FakeAdapter, status;

ResponseBody xml(String path) => ResponseBody.fromString(
  File(path).readAsStringSync(),
  200,
  headers: {
    'content-type': ['application/atom+xml;profile=opds-catalog'],
  },
);

void main() {
  late AppDatabase db;
  late CatalogRepository repo;
  late FakeAdapter adapter;
  late GutenbergSource source;
  final sample = parsePgCatalog(
    File('test/fixtures/catalog/pg_catalog_sample.csv').readAsBytesSync(),
  );
  const popular = 'test/fixtures/catalog/opds_popular.xml';
  const book1342 = 'test/fixtures/catalog/opds_book_1342.xml';

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    repo = CatalogRepository(db);
    await repo.replaceAll(sample);
    adapter = FakeAdapter();
    source = GutenbergSource(
      repo,
      dio: lumaDio()..httpClientAdapter = adapter,
      retryDelay: Duration.zero,
    );
  });
  tearDown(() => db.close());

  test('urls are built from the id, no request per item', () {
    expect(
      GutenbergSource.coverUrl(1342),
      'https://www.gutenberg.org/cache/epub/1342/pg1342.cover.medium.jpg',
    );
    expect(
      GutenbergSource.epubUrl(1342),
      'https://www.gutenberg.org/ebooks/1342.epub.noimages',
    );
  });

  test('empty query = popular from OPDS, authors from the local catalog', () async {
    adapter.queue.add(xml(popular));
    final page = await source.search('', page: 2);
    final request = adapter.requests.single;
    expect(request.uri.path, '/ebooks/search.opds/');
    expect(request.uri.queryParameters, {
      'sort_order': 'downloads',
      'start_index': '26',
    });
    expect(request.headers['User-Agent'], contains('mailto:'));
    expect(page.hasMore, isTrue);
    expect(page.total, isNull);
    expect(page.items, hasLength(25));

    final pride = page.items.first;
    expect(
      pride,
      const CatalogBook(
        sourceId: 'gutenberg',
        externalId: '1342',
        title: 'Pride and Prejudice',
        authors: [CatalogAuthor('Austen, Jane', birth: 1775, death: 1817)],
        coverUrl:
            'https://www.gutenberg.org/cache/epub/1342/pg1342.cover.medium.jpg',
        downloadUrl: 'https://www.gutenberg.org/ebooks/1342.epub.noimages',
      ),
    );
    // Not in the sample catalog: feed title + display name.
    final gatsby = page.items.singleWhere((b) => b.externalId == '64317');
    expect(gatsby.title, 'The Great Gatsby');
    expect(gatsby.authors, const [CatalogAuthor('F. Scott Fitzgerald')]);
    final dictionary = page.items.singleWhere((b) => b.externalId == '37683');
    expect(dictionary.authors, isEmpty);
  });

  test('a query searches the local catalog only', () async {
    final page = await source.search('austen');
    expect(adapter.requests, isEmpty);
    expect(page.items.single.externalId, '1342');
    expect(page.total, 1);
    expect(page.hasMore, isFalse);
    expect((await source.search('zzzz')).total, 0);
  });

  test('503 is retried, then the page comes through', () async {
    adapter.queue.addAll([status(503), xml(popular)]);
    final page = await source.search('');
    expect(adapter.requests, hasLength(2));
    expect(page.items, hasLength(25));
  });

  test('timeout and 404 are not retried', () async {
    adapter.queue.add(DioExceptionType.receiveTimeout);
    await expectLater(
      source.search(''),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.receiveTimeout,
        ),
      ),
    );
    adapter.queue.add(status(404));
    await expectLater(source.fetchDetail('1'), throwsA(isA<DioException>()));
    expect(adapter.requests, hasLength(2));
  });

  test('fetchDetail reads /ebooks/{id}.opds', () async {
    adapter.queue.add(xml(book1342));
    final detail = await source.fetchDetail('1342');
    expect(adapter.requests.single.uri.path, '/ebooks/1342.opds');
    expect(detail.fileSize, 609138);
    expect(detail.summary, isNotNull);
  });

  test('download reports progress and returns the bytes', () async {
    final bytes = List<int>.generate(1000, (i) => i % 256);
    adapter.queue.add(
      ResponseBody.fromBytes(
        bytes,
        200,
        headers: {
          'content-length': ['${bytes.length}'],
        },
      ),
    );
    final progress = <double>[];
    final book = (await source.search('austen')).items.single;
    final result = await source.download(book, onProgress: progress.add);
    expect(result, bytes);
    expect(progress.last, 1.0);
    expect(
      adapter.requests.single.uri.toString(),
      'https://www.gutenberg.org/ebooks/1342.epub.noimages',
    );
    expect(
      adapter.requests.single.receiveTimeout,
      GutenbergSource.downloadTimeout,
    );
  });

  test('cancelled download throws a cancel DioException', () async {
    adapter.queue.add(ResponseBody.fromBytes(const [1, 2, 3], 200));
    final book = (await source.search('austen')).items.single;
    await expectLater(
      source.download(book, isCancelled: () => true),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
  });
}
