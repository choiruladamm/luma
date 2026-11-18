import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/book_repository.dart';
import '../../../../data/repositories/catalog_repository.dart';
import '../../../../data/services/book_source.dart';
import '../../../../domain/models/catalog.dart';
import 'discover_view_model.dart';

/// Detail content from `fetchDetail` (boards 10–13). The screen header doesn't
/// wait for this: title, author, cover are already in `CatalogBook`.
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

/// "N buku lain di katalog": the author's book count in the local catalog minus
/// this book. Its own provider so widget tests can override it without Drift.
final authorBookCountProvider = FutureProvider.autoDispose.family<int, String>(
  (ref, author) async =>
      (await ref.watch(catalogRepositoryProvider).countByAuthor(author) - 1)
          .clamp(0, 1 << 31),
);

/// Shelf book id for this catalog identity; null = not on the shelf. Re-read
/// every time the shelf changes (download finishes → "Baca sekarang" / "Lanjut
/// baca").
final shelfBookIdProvider = FutureProvider.autoDispose
    .family<int?, CatalogBook>((ref, book) {
      ref.watch(shelfExternalIdsProvider(book.sourceId));
      return ref
          .watch(bookRepositoryProvider)
          .idFromSource(book.sourceId, book.externalId);
    });
