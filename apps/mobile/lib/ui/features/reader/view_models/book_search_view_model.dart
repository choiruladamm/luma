import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/book_search_index.dart';
import '../../../../data/repositories/book_search_repository.dart';
import '../../../../domain/book_search.dart';
import '../../../../domain/models/book_search.dart';

/// Tahap sheet Cari kata (board layar 1–5).
enum BookSearchPhase {
  /// Ngecek index buku (sekejap, tanpa tampilan).
  checking,

  /// Buku lama lagi di-index (layar 5).
  preparing,

  /// Belum ada query yang bisa dicari: riwayat (layar 1).
  idle,

  /// Hasil (layar 2–3).
  results,

  /// Gak ketemu (layar 4).
  empty,

  /// Pencarian error.
  failed,
}

class BookSearchState {
  const BookSearchState({
    this.phase = BookSearchPhase.checking,
    this.query = '',
    this.result = BookSearchResult.empty,
    this.recents = const [],
    this.doneChapters = 0,
    this.totalChapters = 0,
  });

  final BookSearchPhase phase;

  /// Isi kolom cari apa adanya.
  final String query;

  /// Hasil buat [query]; kosong di luar [BookSearchPhase.results].
  final BookSearchResult result;
  final List<String> recents;

  /// Progres [BookSearchPhase.preparing].
  final int doneChapters;
  final int totalChapters;

  BookSearchState copyWith({
    BookSearchPhase? phase,
    String? query,
    BookSearchResult? result,
    List<String>? recents,
    int? doneChapters,
    int? totalChapters,
  }) => BookSearchState(
    phase: phase ?? this.phase,
    query: query ?? this.query,
    result: result ?? this.result,
    recents: recents ?? this.recents,
    doneChapters: doneChapters ?? this.doneChapters,
    totalChapters: totalChapters ?? this.totalChapters,
  );
}

extension BookSearchStateLabel on BookSearchState {
  /// Progres nyiapin index 0..1.
  double get prepareFraction =>
      totalChapters == 0 ? 0 : doneChapters / totalChapters;
}

/// ViewModel sheet Cari kata satu buku: nyiapin index kalau perlu, nyari
/// 250 ms abis berhenti ngetik, riwayat. Kolom cari-nya sendiri dipegang
/// view; yang dikirim ke sini [setQuery].
class BookSearchViewModel extends Notifier<BookSearchState> {
  BookSearchViewModel(this.bookId);

  final int bookId;

  /// Jeda abis berhenti ngetik.
  static const debounce = Duration(milliseconds: 250);

  Timer? _timer;
  int _seq = 0;
  bool _ready = false;

  @override
  BookSearchState build() {
    ref.onDispose(() => _timer?.cancel());
    Future(_start);
    return const BookSearchState();
  }

  Future<void> _start() async {
    try {
      final recents = await ref
          .read(bookSearchRepositoryProvider)
          .recentSearches(bookId);
      if (!ref.mounted) return;
      state = state.copyWith(recents: recents);
      final index = ref.read(bookSearchIndexProvider);
      if (!await index.isIndexed(bookId)) {
        if (!ref.mounted) return;
        state = state.copyWith(phase: BookSearchPhase.preparing);
        await index.ensureIndexed(
          bookId,
          onProgress: (done, total) {
            if (!ref.mounted) return;
            state = state.copyWith(doneChapters: done, totalChapters: total);
          },
        );
        if (!ref.mounted) return;
      }
      _ready = true;
      state = state.copyWith(phase: BookSearchPhase.idle);
      if (BookSearchQuery.parse(state.query) != null) await _run();
    } on Object {
      if (ref.mounted) state = state.copyWith(phase: BookSearchPhase.failed);
    }
  }

  /// Isi kolom berubah: cari 250 ms lagi. Kurang dari 2 huruf = balik ke
  /// riwayat.
  void setQuery(String raw) {
    state = state.copyWith(query: raw);
    _timer?.cancel();
    _seq++;
    if (!_ready) return;
    if (BookSearchQuery.parse(raw) == null) {
      state = state.copyWith(
        phase: BookSearchPhase.idle,
        result: BookSearchResult.empty,
      );
      return;
    }
    _timer = Timer(debounce, _run);
  }

  /// Tap riwayat: langsung cari, tanpa jeda.
  Future<void> searchNow(String raw) {
    _timer?.cancel();
    state = state.copyWith(query: raw);
    return _ready ? _run() : Future.value();
  }

  Future<void> _run() async {
    final seq = ++_seq;
    final query = state.query;
    try {
      final result = await ref
          .read(bookSearchRepositoryProvider)
          .search(bookId, query);
      if (seq != _seq || !ref.mounted) return;
      state = state.copyWith(
        phase: result.isEmpty ? BookSearchPhase.empty : BookSearchPhase.results,
        result: result,
      );
    } on Object {
      if (seq != _seq || !ref.mounted) return;
      state = state.copyWith(phase: BookSearchPhase.failed);
    }
  }

  /// Dipanggil pas hasil di-tap: query masuk riwayat (bukan tiap ketikan).
  Future<void> remember() async {
    final repo = ref.read(bookSearchRepositoryProvider);
    await repo.saveRecent(bookId, state.query);
    if (!ref.mounted) return;
    state = state.copyWith(recents: await repo.recentSearches(bookId));
  }

  Future<void> clearRecents() async {
    await ref.read(bookSearchRepositoryProvider).clearRecents(bookId);
    if (ref.mounted) state = state.copyWith(recents: const []);
  }
}

final bookSearchProvider = NotifierProvider.autoDispose
    .family<BookSearchViewModel, BookSearchState, int>(BookSearchViewModel.new);
