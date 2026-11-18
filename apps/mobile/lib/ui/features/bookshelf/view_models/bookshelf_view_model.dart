import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/book_repository.dart';
import '../../../../data/services/file_storage.dart';
import '../../../../domain/models/book.dart';

/// Shelf contents; updates itself whenever a book is added / opened / deleted.
final booksStreamProvider = StreamProvider.autoDispose<List<ShelfBook>>(
  (ref) => ref.watch(bookRepositoryProvider).watchShelf(),
);

/// Contents of the Info buku sheet (date, file size, paragraphs translated).
final bookInfoProvider = FutureProvider.autoDispose.family<BookInfo?, int>(
  (ref, id) => ref
      .watch(bookRepositoryProvider)
      .bookInfo(id, ref.watch(fileStorageProvider)),
);
