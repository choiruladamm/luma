import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/book_repository.dart';
import '../../../../domain/models/book.dart';

/// Isi rak, update sendiri tiap ada buku masuk / dibuka / dihapus.
final booksStreamProvider = StreamProvider.autoDispose<List<ShelfBook>>(
  (ref) => ref.watch(bookRepositoryProvider).watchShelf(),
);
