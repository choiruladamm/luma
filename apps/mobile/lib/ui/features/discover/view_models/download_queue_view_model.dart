import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/import_repository.dart';
import '../../../../data/services/book_source.dart';
import '../../../../domain/models/catalog.dart';

enum DownloadStatus {
  queued,
  downloading,
  importing,

  /// Udah di rak, [DownloadItem.bookId] buku barunya.
  done,

  /// File yang sama udah ada; [DownloadItem.bookId] nunjuk yang lama.
  duplicate,
  failed,
}

class DownloadItem {
  const DownloadItem({
    required this.book,
    this.status = DownloadStatus.queued,
    this.progress = 0,
    this.bookId,
    this.error,
  });

  final CatalogBook book;
  final DownloadStatus status;

  /// 0–1 selama unduh (−1 kalau server gak kasih panjang).
  final double progress;
  final int? bookId;

  /// `DioException` (jaringan) atau `EpubException` (file rusak).
  final Object? error;

  String get key => '${book.sourceId}/${book.externalId}';

  bool get finished => switch (status) {
    DownloadStatus.done ||
    DownloadStatus.duplicate ||
    DownloadStatus.failed => true,
    DownloadStatus.queued ||
    DownloadStatus.downloading ||
    DownloadStatus.importing => false,
  };

  DownloadItem copyWith({
    DownloadStatus? status,
    double? progress,
    int? bookId,
    Object? error,
  }) => DownloadItem(
    book: book,
    status: status ?? this.status,
    progress: progress ?? this.progress,
    bookId: bookId ?? this.bookId,
    error: error ?? this.error,
  );
}

/// Antrian download level app (docs/discover.md, Keputusan): satu jalan,
/// sisanya nunggu; pindah layar gak batal, cuma app kill yang motong.
/// Selesai → `importEpub` (dedup sha256) → toast lewat [DownloadToasts].
class DownloadQueue extends Notifier<List<DownloadItem>> {
  @override
  List<DownloadItem> build() => const [];

  bool _running = false;
  String? _cancelKey;

  /// Buku yang lagi antri / jalan gak ditambah dua kali; yang udah selesai
  /// diganti entri baru.
  void enqueue(CatalogBook book) {
    final key = '${book.sourceId}/${book.externalId}';
    final current = _find(key);
    if (current != null && !current.finished) return;
    state = [
      for (final item in state)
        if (item.key != key) item,
      DownloadItem(book: book),
    ];
    _pump();
  }

  /// Antri → langsung hilang. Lagi jalan → ditandain, unduhan / import
  /// berhenti di checkpoint berikutnya lalu entrinya hilang.
  void cancel(String key) {
    final item = _find(key);
    if (item == null) return;
    if (item.status == DownloadStatus.queued) {
      _remove(key);
    } else if (!item.finished) {
      _cancelKey = key;
    }
  }

  /// Buang entri yang udah selesai / gagal dari daftar.
  void dismiss(String key) {
    if (_find(key)?.finished ?? false) _remove(key);
  }

  DownloadItem? _find(String key) =>
      state.where((i) => i.key == key).firstOrNull;

  // Dicek `ref.mounted`: download jalan nyebrang async gap, container bisa
  // keburu dispose (test / app kill).
  void _remove(String key) {
    if (!ref.mounted) return;
    state = [
      for (final i in state)
        if (i.key != key) i,
    ];
  }

  void _update(String key, DownloadItem Function(DownloadItem) change) {
    if (!ref.mounted) return;
    state = [for (final i in state) i.key == key ? change(i) : i];
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        if (!ref.mounted) break;
        final next = state
            .where((i) => i.status == DownloadStatus.queued)
            .firstOrNull;
        if (next == null) break;
        await _run(next);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _run(DownloadItem item) async {
    final key = item.key;
    final book = item.book;
    final source = ref
        .read(bookSourcesProvider)
        .firstWhere((s) => s.id == book.sourceId);
    bool cancelled() => _cancelKey == key;
    try {
      _update(key, (i) => i.copyWith(status: DownloadStatus.downloading));
      final bytes = await source.download(
        book,
        onProgress: (p) => _update(key, (i) => i.copyWith(progress: p)),
        isCancelled: cancelled,
      );
      _update(
        key,
        (i) => i.copyWith(status: DownloadStatus.importing, progress: 1),
      );
      final result = await ref
          .read(importRepositoryProvider)
          .importEpub(
            bytes,
            fileName: 'pg${book.externalId}.epub',
            sourceId: book.sourceId,
            externalId: book.externalId,
            isCancelled: cancelled,
          );
      _update(
        key,
        (i) => i.copyWith(
          status: result.duplicate
              ? DownloadStatus.duplicate
              : DownloadStatus.done,
          bookId: result.bookId,
        ),
      );
    } on ImportCancelled {
      _remove(key);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        _remove(key);
      } else {
        _update(
          key,
          (i) => i.copyWith(status: DownloadStatus.failed, error: e),
        );
      }
    } catch (e) {
      _update(key, (i) => i.copyWith(status: DownloadStatus.failed, error: e));
    } finally {
      if (_cancelKey == key) _cancelKey = null;
    }
  }
}

final downloadQueueProvider =
    NotifierProvider<DownloadQueue, List<DownloadItem>>(DownloadQueue.new);
