import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/book_repository.dart';
import '../../../../data/repositories/catalog_repository.dart';
import '../../../../data/services/book_source.dart';
import '../../../../domain/models/catalog.dart';
import 'discover_view_model.dart';

/// Isi detail dari `fetchDetail` (board 10–13). Kepala layar gak nunggu ini:
/// judul, penulis, cover udah ada di `CatalogBook`.
sealed class DetailState {
  const DetailState();
}

class DetailLoading extends DetailState {
  const DetailLoading({this.slow = false});

  final bool slow;
}

class DetailReady extends DetailState {
  const DetailReady(this.detail);

  final CatalogBookDetail detail;
}

class DetailFailed extends DetailState {
  const DetailFailed(this.failure);

  final NetworkFailure failure;
}

class BookDetailViewModel extends Notifier<DetailState> {
  BookDetailViewModel(this.book);

  final CatalogBook book;
  int _seq = 0;
  Timer? _slow;

  @override
  DetailState build() {
    ref.onDispose(() => _slow?.cancel());
    Future(load);
    return const DetailLoading();
  }

  Future<void> load() async {
    final seq = ++_seq;
    state = const DetailLoading();
    _slow?.cancel();
    _slow = Timer(DiscoverViewModel.slowAfter, () {
      if (seq == _seq && state is DetailLoading) {
        state = const DetailLoading(slow: true);
      }
    });
    final source = ref
        .read(bookSourcesProvider)
        .firstWhere((s) => s.id == book.sourceId);
    try {
      final detail = await source.fetchDetail(book.externalId);
      if (seq != _seq || !ref.mounted) return;
      state = DetailReady(detail);
    } catch (e) {
      if (seq != _seq || !ref.mounted) return;
      state = DetailFailed(DiscoverViewModel.failureOf(e));
    } finally {
      _slow?.cancel();
    }
  }
}

final bookDetailProvider = NotifierProvider.autoDispose
    .family<BookDetailViewModel, DetailState, CatalogBook>(
      BookDetailViewModel.new,
    );

/// "N buku lain di katalog": jumlah buku penulis di katalog lokal dikurangi
/// buku ini. Provider sendiri biar widget test bisa override tanpa Drift.
final authorBookCountProvider = FutureProvider.autoDispose.family<int, String>(
  (ref, author) async =>
      (await ref.watch(catalogRepositoryProvider).countByAuthor(author) - 1)
          .clamp(0, 1 << 31),
);

/// Id buku di rak buat identitas katalog ini; null = belum ada. Dibaca ulang
/// tiap rak berubah (download kelar → "Baca sekarang" / "Lanjut baca").
final shelfBookIdProvider = FutureProvider.autoDispose
    .family<int?, CatalogBook>((ref, book) {
      ref.watch(shelfExternalIdsProvider(book.sourceId));
      return ref
          .watch(bookRepositoryProvider)
          .idFromSource(book.sourceId, book.externalId);
    });
