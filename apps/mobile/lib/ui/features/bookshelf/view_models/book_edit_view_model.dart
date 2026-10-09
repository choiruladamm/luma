import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/book_repository.dart';
import 'bookshelf_view_model.dart';

/// State sheet Ubah judul & penulis (board 33–38).
class BookEditState {
  const BookEditState({
    required this.title,
    required this.author,
    required this.useDefaultCover,
    this.originalTitle,
    this.originalAuthor,
    this.epubCoverName,
    this.saving = false,
  });

  final String title, author;
  final bool useDefaultCover, saving;

  /// Null = belum pernah diedit, gak ada yang bisa dibalikin.
  final String? originalTitle, originalAuthor;

  /// Cover mentah EPUB; null = gak ada, toggle cover disembunyiin.
  final String? epubCoverName;

  bool get titleEmpty => title.trim().isEmpty;
  String? get titleError => titleEmpty ? 'Judul gak boleh kosong' : null;
  bool get canSave => !titleEmpty && !saving;
  bool get canRevert => originalTitle != null;

  BookEditState copyWith({
    String? title,
    String? author,
    bool? useDefaultCover,
    bool? saving,
  }) => BookEditState(
    title: title ?? this.title,
    author: author ?? this.author,
    useDefaultCover: useDefaultCover ?? this.useDefaultCover,
    originalTitle: originalTitle,
    originalAuthor: originalAuthor,
    epubCoverName: epubCoverName,
    saving: saving ?? this.saving,
  );
}

class BookEditViewModel extends Notifier<BookEditState> {
  BookEditViewModel(this.bookId);

  final int bookId;

  @override
  BookEditState build() {
    final shelf = ref
        .read(booksStreamProvider)
        .value
        ?.where((b) => b.id == bookId)
        .firstOrNull;
    final info = ref.read(bookInfoProvider(bookId)).value;
    return BookEditState(
      title: shelf?.title ?? '',
      author: shelf?.author ?? '',
      useDefaultCover: info?.useDefaultCover ?? false,
      originalTitle: info?.originalTitle,
      originalAuthor: info?.originalAuthor,
      epubCoverName: info?.epubCoverName,
    );
  }

  void setTitle(String v) => state = state.copyWith(title: v);
  void setAuthor(String v) => state = state.copyWith(author: v);
  void setUseDefaultCover(bool v) => state = state.copyWith(useDefaultCover: v);

  /// Ngisi ulang field dengan nilai asli EPUB; baru kesimpen pas [save].
  void revert() {
    if (!state.canRevert) return;
    state = state.copyWith(
      title: state.originalTitle,
      author: state.originalAuthor ?? '',
    );
  }

  /// False kalau gagal / judul kosong.
  Future<bool> save() async {
    if (!state.canSave) return false;
    state = state.copyWith(saving: true);
    try {
      await ref
          .read(bookRepositoryProvider)
          .updateMetadata(
            bookId,
            title: state.title.trim(),
            author: state.author.trim().isEmpty ? null : state.author.trim(),
            useDefaultCover: state.useDefaultCover,
          );
      ref.invalidate(bookInfoProvider(bookId));
      return true;
    } on Object {
      state = state.copyWith(saving: false);
      return false;
    }
  }
}

final bookEditProvider = NotifierProvider.autoDispose
    .family<BookEditViewModel, BookEditState, int>(BookEditViewModel.new);
