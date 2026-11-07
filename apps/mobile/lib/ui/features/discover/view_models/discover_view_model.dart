import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/book_repository.dart';
import '../../../../data/services/book_source.dart';
import '../../../../data/services/catalog_sync_service.dart';
import '../../../../domain/models/catalog.dart';

/// Kenapa jalur jaringan gagal (layar 08 / 09).
enum NetworkFailure { offline, dead }

/// "Lagi rame" (board 03, 07, 08, 09).
sealed class PopularState {
  const PopularState();
}

class PopularLoading extends PopularState {
  const PopularLoading({this.slow = false});

  /// Udah lewat 5 detik: layar 07, skeleton tetap jalan.
  final bool slow;
}

class PopularReady extends PopularState {
  const PopularReady(this.items);

  final List<CatalogBook> items;
}

class PopularFailed extends PopularState {
  const PopularFailed(this.failure);

  final NetworkFailure failure;
}

/// Hasil cari dari katalog lokal (board 04, 05, 06). Null di [DiscoverState]
/// = kolom cari kosong.
class SearchResults {
  const SearchResults({
    required this.query,
    required this.items,
    required this.total,
    required this.hasMore,
    this.loadingMore = false,
    this.moreFailed = false,
  });

  final String query;
  final List<CatalogBook> items;
  final int total;
  final bool hasMore;
  final bool loadingMore;
  final bool moreFailed;

  SearchResults copyWith({
    List<CatalogBook>? items,
    bool? hasMore,
    bool? loadingMore,
    bool? moreFailed,
  }) => SearchResults(
    query: query,
    items: items ?? this.items,
    total: total,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
    moreFailed: moreFailed ?? this.moreFailed,
  );
}

class DiscoverState {
  const DiscoverState({
    this.query = '',
    this.popular = const PopularLoading(),
    this.results,
  });

  final String query;
  final PopularState popular;
  final SearchResults? results;

  DiscoverState copyWith({
    String? query,
    PopularState? popular,
    SearchResults? Function()? results,
  }) => DiscoverState(
    query: query ?? this.query,
    popular: popular ?? this.popular,
    results: results == null ? this.results : results(),
  );
}

/// Tab Cari buku (docs/discover.md, Board). Satu sumber dulu: yang pertama di
/// [bookSourcesProvider]. Cari = katalog lokal, instan; populer = jaringan.
class DiscoverViewModel extends Notifier<DiscoverState> {
  static const slowAfter = Duration(seconds: 5);
  static const topCount = 10;
  static const presets = [
    'Sherlock Holmes',
    'Dickens',
    'Shakespeare',
    'Poe',
    'Tolstoy',
  ];

  BookSource get _source => ref.read(bookSourcesProvider).first;
  int _searchSeq = 0;
  int _popularSeq = 0;
  Timer? _slowTimer;

  @override
  DiscoverState build() {
    ref.onDispose(() => _slowTimer?.cancel());
    // Katalog > 7 hari: sync diam-diam (service yang mutusin skip / unduh).
    Future(() => ref.read(catalogSyncProvider.notifier).sync());
    Future(loadPopular);
    return const DiscoverState();
  }

  Future<void> loadPopular() async {
    final seq = ++_popularSeq;
    state = state.copyWith(popular: const PopularLoading());
    _slowTimer?.cancel();
    final slowTimer = _slowTimer = Timer(slowAfter, () {
      if (seq == _popularSeq && state.popular is PopularLoading) {
        state = state.copyWith(popular: const PopularLoading(slow: true));
      }
    });
    try {
      final page = await _source.search('');
      if (seq != _popularSeq || !ref.mounted) return;
      state = state.copyWith(
        popular: PopularReady(page.items.take(topCount).toList()),
      );
    } catch (e) {
      if (seq != _popularSeq || !ref.mounted) return;
      state = state.copyWith(popular: PopularFailed(failureOf(e)));
    } finally {
      slowTimer.cancel();
    }
  }

  /// Tiap ketikan: kosong = balik ke populer, selain itu cari halaman 1.
  Future<void> setQuery(String query) async {
    final seq = ++_searchSeq;
    final q = query.trim();
    if (q.isEmpty) {
      state = state.copyWith(query: query, results: () => null);
      return;
    }
    state = state.copyWith(query: query);
    final page = await _source.search(q);
    if (seq != _searchSeq || !ref.mounted) return;
    state = state.copyWith(
      results: () => SearchResults(
        query: q,
        items: page.items,
        total: page.total ?? page.items.length,
        hasMore: page.hasMore,
      ),
    );
  }

  /// Mentok bawah: halaman berikutnya (25). Gagal = footer "Coba lagi".
  Future<void> loadMore() async {
    final r = state.results;
    if (r == null || !r.hasMore || r.loadingMore) return;
    final seq = _searchSeq;
    state = state.copyWith(
      results: () => r.copyWith(loadingMore: true, moreFailed: false),
    );
    try {
      final page = await _source.search(
        r.query,
        page: r.items.length ~/ 25 + 1,
      );
      if (seq != _searchSeq || !ref.mounted) return;
      state = state.copyWith(
        results: () => r.copyWith(
          items: [...r.items, ...page.items],
          hasMore: page.hasMore,
          loadingMore: false,
          moreFailed: false,
        ),
      );
    } catch (_) {
      if (seq != _searchSeq || !ref.mounted) return;
      state = state.copyWith(
        results: () => r.copyWith(loadingMore: false, moreFailed: true),
      );
    }
  }

  static NetworkFailure failureOf(Object e) {
    if (e is DioException &&
        (e.type == DioExceptionType.connectionError ||
            e.error is SocketException)) {
      return NetworkFailure.offline;
    }
    if (e is SocketException) return NetworkFailure.offline;
    return NetworkFailure.dead;
  }
}

final discoverProvider =
    NotifierProvider.autoDispose<DiscoverViewModel, DiscoverState>(
      DiscoverViewModel.new,
    );

/// `externalId` yang udah di rak buat badge "Udah di rak".
final shelfExternalIdsProvider = StreamProvider.autoDispose
    .family<Set<String>, String>(
      (ref, sourceId) =>
          ref.watch(bookRepositoryProvider).watchExternalIds(sourceId),
    );
