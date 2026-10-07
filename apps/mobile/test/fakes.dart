import 'dart:async';

import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/domain/models/reader_prefs.dart';
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

/// Settings without a database: serves [prefs], emits every save.
class FakeSettings implements SettingsRepository {
  FakeSettings([this.prefs = const ReaderPrefs()]);

  ReaderPrefs prefs;
  final _saves = StreamController<ReaderPrefs>.broadcast();

  @override
  Stream<ReaderPrefs> watchReaderPrefs() async* {
    yield prefs;
    yield* _saves.stream;
  }

  @override
  Future<void> saveReaderPrefs(ReaderPrefs p) async {
    prefs = p;
    _saves.add(p);
  }
}
