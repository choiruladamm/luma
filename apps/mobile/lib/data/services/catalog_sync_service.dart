import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/catalog/pg_catalog_parser.dart';
import '../repositories/catalog_repository.dart';
import 'http_client.dart';

enum CatalogSyncResult {
  /// The local catalog is still fresh (under 7 days old), so the server is not contacted.
  skipped,

  /// The server answered 304: the dump is unchanged and only `syncedAt` advances.
  notModified,

  /// The table was replaced with the new dump.
  updated,
}

/// Downloads `pg_catalog.csv.gz` and loads it via `CatalogRepository.replaceAll`
/// (docs/discover.md, Local catalog and search).
///
/// Any failure leaves the old table intact.
class CatalogSyncService {
  CatalogSyncService(
    this._repo, {
    Dio? dio,
    this.retryDelay = const Duration(seconds: 2),
    DateTime Function()? now,
  }) : _dio = dio ?? lumaDio(receiveTimeout: const Duration(seconds: 120)),
       _now = now ?? DateTime.now;

  final CatalogRepository _repo;
  final Dio _dio;
  final DateTime Function() _now;

  /// Delay before retry n is [retryDelay] × n.
  final Duration retryDelay;

  static const url =
      'https://www.gutenberg.org/cache/epub/feeds/pg_catalog.csv.gz';
  static const maxAge = Duration(days: 7);

  /// Syncs the catalog and returns what happened.
  ///
  /// [onProgress] reports 0–1 while downloading (−1 when the server sends no
  /// length); [onImporting] fires when the download ends and parsing starts.
  /// Cancelling through [cancel] throws a `DioException` of type `cancel`.
  Future<CatalogSyncResult> sync({
    bool force = false,
    void Function(double progress)? onProgress,
    void Function()? onImporting,
    CancelToken? cancel,
  }) async {
    final stats = await _repo.stats();
    final fresh =
        stats.count > 0 &&
        stats.syncedAt != null &&
        _now().difference(stats.syncedAt!) < maxAge;
    if (!force && fresh) return CatalogSyncResult.skipped;

    final dir = await Directory.systemTemp.createTemp('luma-catalog-');
    try {
      final path = '${dir.path}/pg_catalog.csv.gz';
      final response = await _download(
        path,
        // An empty table must download even if the server says nothing changed.
        since: stats.count > 0 ? stats.lastModified : null,
        onProgress: onProgress,
        cancel: cancel,
      );
      if (response.statusCode == 304) {
        await _repo.saveMeta(syncedAt: _now());
        return CatalogSyncResult.notModified;
      }
      onImporting?.call();
      final rows = await Isolate.run(
        () => parsePgCatalog(
          GZipDecoder().decodeBytes(File(path).readAsBytesSync()),
        ),
      );
      if (rows.isEmpty) throw const FormatException('Katalog kosong');
      await _repo.replaceAll(rows);
      await _repo.saveMeta(
        syncedAt: _now(),
        lastModified: response.headers.value('last-modified'),
        count: rows.length,
      );
      return CatalogSyncResult.updated;
    } finally {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // Already gone; not a problem.
      }
    }
  }

  /// Streams the download to [path]; retries 429/503 up to 3 times and throws on any other status.
  Future<Response<dynamic>> _download(
    String path, {
    String? since,
    void Function(double progress)? onProgress,
    CancelToken? cancel,
  }) => retryOnBusy(
    delay: retryDelay,
    () => _dio.download(
      url,
      path,
      cancelToken: cancel,
      onReceiveProgress: (received, total) =>
          onProgress?.call(total > 0 ? received / total : -1),
      options: Options(
        headers: {'If-Modified-Since': ?since},
        validateStatus: (s) => s == 200 || s == 304,
      ),
    ),
  );
}

final catalogSyncServiceProvider = Provider<CatalogSyncService>(
  (ref) => CatalogSyncService(ref.watch(catalogRepositoryProvider)),
);

/// Catalog sync state.
///
/// The idle text (date, count) comes from [catalogStatsProvider], not from here.
sealed class CatalogSyncState {
  const CatalogSyncState();
}

class CatalogSyncIdle extends CatalogSyncState {
  const CatalogSyncIdle();
}

/// Asking the server (If-Modified-Since); no bytes received yet.
class CatalogSyncChecking extends CatalogSyncState {
  const CatalogSyncChecking();
}

class CatalogSyncDownloading extends CatalogSyncState {
  const CatalogSyncDownloading(this.progress);

  /// Fraction from 0 to 1; −1 means the server sent no length.
  final double progress;
}

/// Gunzipping, parsing, and replacing the table; cannot be cancelled.
class CatalogSyncImporting extends CatalogSyncState {
  const CatalogSyncImporting();
}

/// The server answered 304; shown once as a toast, then [CatalogSyncController.dismiss].
class CatalogSyncUpToDate extends CatalogSyncState {
  const CatalogSyncUpToDate();
}

class CatalogSyncFailed extends CatalogSyncState {
  const CatalogSyncFailed(this.reason);

  /// For logs and debugging; the UI shows fixed copy.
  final String reason;
}

/// Runs one sync at a time; `sync()` while one is running is a no-op.
///
/// Not autoDispose, so leaving the screen does not cut the download.
class CatalogSyncController extends Notifier<CatalogSyncState> {
  CancelToken? _cancel;

  @override
  CatalogSyncState build() => const CatalogSyncIdle();

  bool get _running => switch (state) {
    CatalogSyncChecking() ||
    CatalogSyncDownloading() ||
    CatalogSyncImporting() => true,
    CatalogSyncIdle() || CatalogSyncUpToDate() || CatalogSyncFailed() => false,
  };

  Future<void> sync({bool force = false}) async {
    if (_running) return;
    final cancel = _cancel = CancelToken();
    state = const CatalogSyncChecking();
    try {
      final result = await ref
          .read(catalogSyncServiceProvider)
          .sync(
            force: force,
            cancel: cancel,
            onProgress: (p) {
              if (!cancel.isCancelled) state = CatalogSyncDownloading(p);
            },
            onImporting: () => state = const CatalogSyncImporting(),
          );
      state = result == CatalogSyncResult.notModified
          ? const CatalogSyncUpToDate()
          : const CatalogSyncIdle();
    } on DioException catch (e) {
      state = e.type == DioExceptionType.cancel
          ? const CatalogSyncIdle()
          : CatalogSyncFailed(
              e.response != null
                  ? 'HTTP ${e.response!.statusCode}'
                  : e.type.name,
            );
    } catch (e) {
      state = CatalogSyncFailed(e.toString());
    }
  }

  /// Cancels only while downloading; parsing and the table swap are left to finish.
  void cancel() {
    if (state is CatalogSyncDownloading) _cancel?.cancel();
  }

  /// Clears the up-to-date state once its toast has been shown.
  void dismiss() {
    if (state is CatalogSyncUpToDate) state = const CatalogSyncIdle();
  }
}

final catalogSyncProvider =
    NotifierProvider<CatalogSyncController, CatalogSyncState>(
      CatalogSyncController.new,
    );
