import 'models/book.dart';

/// [books] datang urut terakhir dibuka (urutan stream rak).
List<ShelfBook> sortShelf(List<ShelfBook> books, ShelfSort sort) =>
    switch (sort) {
      ShelfSort.lastOpened => books,
      ShelfSort.title => [
        ...books,
      ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase())),
      ShelfSort.added =>
        [...books]..sort((a, b) {
          final byDate = b.createdAt.compareTo(a.createdAt);
          return byDate != 0 ? byDate : b.id.compareTo(a.id);
        }),
    };
