import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/catalog/pg_catalog_parser.dart';
import '../../domain/models/backup.dart';
import '../repositories/catalog_repository.dart';

enum CatalogSyncResult {
  /// Masih segar (< 7 hari), gak ke server.
  skipped,

  /// Server bilang 304: dump belum berubah, cuma `syncedAt` yang maju.
  notModified,

  /// Tabel diganti isi dump baru.
  updated,
}

/// Ngunduh `pg_catalog.csv.gz` → `CatalogRepository.replaceAll`
/// (docs/discover.md, Katalog lokal). Gagal apa pun = tabel lama utuh.
class CatalogSyncService {
  CatalogSyncService(
    this._repo, {
    Dio? dio,
    this.retryDelay = const Duration(seconds: 2),
    DateTime Function()? now,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 120),
               headers: {'User-Agent': userAgent},
             ),
           ),
       _now = now ?? DateTime.now;

  final CatalogRepository _repo;
  final Dio _dio;
  final DateTime Function() _now;

  /// Jeda retry ke-n = [retryDelay] × n.
  final Duration retryDelay;

  static const url =
      'https://www.gutenberg.org/cache/epub/feeds/pg_catalog.csv.gz';
  static const maxAge = Duration(days: 7);

  /// Kebijakan gutenberg.org: UA tanpa kontak diblok IP.
  static const userAgent = 'Luma/$appVersion (+mailto:work.adamm@gmail.com)';

  /// [onProgress] 0–1 selama unduh (−1 kalau server gak kasih panjang),
  /// [onImporting] pas unduhan selesai dan parse mulai. Batal lewat
  /// [cancel] → `DioException` tipe `cancel`.
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
        // Tabel kosong harus ngunduh walau server bilang belum berubah.
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
        // Udah keburu kehapus; bukan masalah.
      }
    }
  }

  /// Streaming ke [path]. 429/503 dicoba ulang sampe 3×; status lain lempar.
  Future<Response<dynamic>> _download(
    String path, {
    String? since,
    void Function(double progress)? onProgress,
    CancelToken? cancel,
  }) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await _dio.download(
          url,
          path,
          cancelToken: cancel,
          onReceiveProgress: (received, total) =>
              onProgress?.call(total > 0 ? received / total : -1),
          options: Options(
            headers: {'If-Modified-Since': ?since},
            validateStatus: (s) => s == 200 || s == 304,
          ),
        );
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        if (attempt >= 3 || (status != 429 && status != 503)) rethrow;
        await Future<void>.delayed(retryDelay * attempt);
      }
    }
  }
}

final catalogSyncServiceProvider = Provider<CatalogSyncService>(
  (ref) => CatalogSyncService(ref.watch(catalogRepositoryProvider)),
);

/// Keadaan sync katalog; teks idle (tanggal, jumlah) dari
/// [catalogStatsProvider], bukan dari sini.
sealed class CatalogSyncState {
  const CatalogSyncState();
}

class CatalogSyncIdle extends CatalogSyncState {
  const CatalogSyncIdle();
}

/// Nanya server (If-Modified-Since), belum ada byte.
class CatalogSyncChecking extends CatalogSyncState {
  const CatalogSyncChecking();
}

class CatalogSyncDownloading extends CatalogSyncState {
  const CatalogSyncDownloading(this.progress);

  /// 0–1; −1 = server gak kasih panjang.
  final double progress;
}

/// Gunzip + parse + ganti tabel; gak bisa dibatalin.
class CatalogSyncImporting extends CatalogSyncState {
  const CatalogSyncImporting();
}

/// 304: cuma sekali tampil sebagai toast, lalu [CatalogSyncController.dismiss].
class CatalogSyncUpToDate extends CatalogSyncState {
  const CatalogSyncUpToDate();
}

class CatalogSyncFailed extends CatalogSyncState {
  const CatalogSyncFailed(this.reason);

  /// Buat log/debug; UI nampilin copy tetap.
  final String reason;
}

/// Satu sync jalan sekaligus; `sync()` pas lagi jalan = no-op. Tanpa
/// autoDispose: pindah layar gak motong unduhan.
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

  /// Cuma pas ngunduh; parse/ganti tabel dibiarin selesai.
  void cancel() {
    if (state is CatalogSyncDownloading) _cancel?.cancel();
  }

  /// Toast "udah yang terbaru" udah tampil.
  void dismiss() {
    if (state is CatalogSyncUpToDate) state = const CatalogSyncIdle();
  }
}

final catalogSyncProvider =
    NotifierProvider<CatalogSyncController, CatalogSyncState>(
      CatalogSyncController.new,
    );
