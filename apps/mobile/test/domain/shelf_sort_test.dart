import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/models/book.dart';
import 'package:luma/domain/shelf_sort.dart';

ShelfBook b(int id, String title, int day) => ShelfBook(
  id: id,
  title: title,
  author: null,
  coverName: null,
  opened: true,
  createdAt: DateTime(2026, 10, day),
);

void main() {
  // Stream order = last opened first.
  final books = [b(1, 'walden', 1), b(2, 'Dracula', 3), b(3, 'Emma', 3)];
  List<int> ids(ShelfSort s) => sortShelf(books, s).map((x) => x.id).toList();

  test('last opened keeps the stream order', () {
    expect(ids(ShelfSort.lastOpened), [1, 2, 3]);
  });

  test('title is A-Z ignoring case', () {
    expect(ids(ShelfSort.title), [2, 3, 1]);
  });

  test('added is newest first, newest id first on a tie', () {
    expect(ids(ShelfSort.added), [3, 2, 1]);
  });

  test('sorting does not touch the input list', () {
    sortShelf(books, ShelfSort.title);
    expect(books.map((x) => x.id), [1, 2, 3]);
  });
}
