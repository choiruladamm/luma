import 'package:luma/data/repositories/reading_progress_repository.dart';

/// Reading progress without a database: records saves, serves [saved].
class FakeProgress implements ReadingProgressRepository {
  FakeProgress([this.saved]);

  ReadingPosition? saved;
  final saves = <ReadingPosition>[];
  final opened = <int>[];
  int readingSeconds = 0;

  @override
  Future<ReadingPosition?> load(int bookId) async => saved;

  @override
  Future<void> save(int bookId, ReadingPosition position) async =>
      saves.add(position);

  @override
  Future<void> markOpened(int bookId) async => opened.add(bookId);

  @override
  Future<void> addReadingTime(int bookId, int seconds) async =>
      readingSeconds += seconds;
}
