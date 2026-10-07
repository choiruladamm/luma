import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/book_repository.dart';
import '../../../../data/services/file_storage.dart';
import '../../../../domain/models/book.dart';

/// Isi rak, update sendiri tiap ada buku masuk / dibuka / dihapus.
final booksStreamProvider = StreamProvider.autoDispose<List<ShelfBook>>(
  (ref) => ref.watch(bookRepositoryProvider).watchShelf(),
);

/// Isi sheet Info buku (tanggal, ukuran file, paragraf diartiin).
final bookInfoProvider = FutureProvider.autoDispose.family<BookInfo?, int>(
  (ref, id) => ref
      .watch(bookRepositoryProvider)
      .bookInfo(id, ref.watch(fileStorageProvider)),
);
