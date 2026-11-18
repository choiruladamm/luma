import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/book_repository.dart';
import 'bookshelf_view_model.dart';

/// State of the Ubah judul & penulis sheet (boards 33–38).
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

  /// Null = never edited, nothing to restore.
  final String? originalTitle, originalAuthor;

  /// Raw EPUB cover; null = none, the cover toggle is hidden.
  final String? epubCoverName;

  bool get titleEmpty => title.trim().isEmpty;

  /// Trimmed author; empty = null.
  String? get authorOrNull {
    final a = author.trim();
    return a.isEmpty ? null : a;
  }

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

  /// Refills the fields with the original EPUB values; only saved on [save].
  void revert() {
    if (!state.canRevert) return;
    state = state.copyWith(
      title: state.originalTitle,
      author: state.originalAuthor ?? '',
    );
  }

  /// False on failure / empty title.
  Future<bool> save() async {
    if (!state.canSave) return false;
    state = state.copyWith(saving: true);
    try {
      await ref
          .read(bookRepositoryProvider)
          .updateMetadata(
            bookId,
            title: state.title.trim(),
            author: state.authorOrNull,
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
