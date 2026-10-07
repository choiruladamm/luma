import 'dart:async';

import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/data/services/openrouter_service.dart';
import 'package:luma/domain/models/ai_model.dart';
import 'package:luma/domain/models/ai_reply.dart';
import 'package:luma/domain/models/backup.dart';
import 'package:luma/domain/models/book.dart';
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

  ShelfSort shelfSort = ShelfSort.lastOpened;
  final _sorts = StreamController<ShelfSort>.broadcast();

  @override
  Stream<ShelfSort> watchShelfSort() async* {
    yield shelfSort;
    yield* _sorts.stream;
  }

  @override
  Future<void> saveShelfSort(ShelfSort sort) async {
    shelfSort = sort;
    _sorts.add(sort);
  }

  ShelfView shelfView = ShelfView.grid;
  final _views = StreamController<ShelfView>.broadcast();

  @override
  Stream<ShelfView> watchShelfView() async* {
    yield shelfView;
    yield* _views.stream;
  }

  @override
  Future<void> saveShelfView(ShelfView view) async {
    shelfView = view;
    _views.add(view);
  }

  LastBackup? lastBackup;
  final _backups = StreamController<LastBackup?>.broadcast();

  @override
  Stream<LastBackup?> watchLastBackup() async* {
    yield lastBackup;
    yield* _backups.stream;
  }

  @override
  Future<void> saveLastBackup(LastBackup b) async {
    lastBackup = b;
    _backups.add(b);
  }

  DateTime? dismissed;
  final _dismissals = StreamController<DateTime?>.broadcast();

  @override
  Stream<DateTime?> watchReminderDismissed() async* {
    yield dismissed;
    yield* _dismissals.stream;
  }

  @override
  Future<void> dismissReminder(DateTime at) async {
    dismissed = at;
    _dismissals.add(at);
  }

  String model = defaultAiModel;
  final _models = StreamController<String>.broadcast();

  @override
  Stream<String> watchModel() async* {
    yield model;
    yield* _models.stream;
  }

  @override
  Future<void> saveModel(String id) async {
    model = id;
    _models.add(id);
  }
}

/// OpenRouter without the network. [keyOk] null = can't reach it.
/// [explain] answers "id: " + each target paragraph, or throws [failure].
class FakeOpenRouter implements OpenRouterService {
  bool? keyOk = true;

  /// Kalau diisi, checkKey nunggu sampai selesai (cek yang lagi jalan).
  Completer<void>? gate;
  final checked = <String>[];
  final calls =
      <
        ({
          String? apiKey,
          String model,
          List<String> context,
          List<String> target,
        })
      >[];
  AiException? failure;

  @override
  Future<bool> checkKey(String apiKey) async {
    checked.add(apiKey);
    await gate?.future;
    if (keyOk == null) throw const AiException(AiError.network);
    return keyOk!;
  }

  @override
  Future<AiReply> explain({
    required String? apiKey,
    required String model,
    required List<String> context,
    required List<String> target,
  }) async {
    calls.add((apiKey: apiKey, model: model, context: context, target: target));
    if (apiKey == null) throw const AiException(AiError.noApiKey);
    if (failure != null) throw failure!;
    return AiReply(
      translations: [for (final t in target) 'id: $t'],
      meaning: 'Maknanya: ${target.length} paragraf.',
    );
  }
}
