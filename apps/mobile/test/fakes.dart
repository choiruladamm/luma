import 'dart:async';

import 'package:dio/dio.dart';

import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/data/services/openrouter_service.dart';
import 'package:luma/domain/ai_prompt.dart';
import 'package:luma/domain/breakdown_prompt.dart';
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
  final finished = <int>[];
  int readingSeconds = 0;

  /// One entry per `addReadingTime` call that carried a span.
  final spans = <ReadingSpan>[];

  @override
  Future<ReadingPosition?> load(int bookId) async => saved;

  @override
  Future<void> save(int bookId, ReadingPosition position) async =>
      saves.add(position);

  @override
  Future<void> markOpened(int bookId) async => opened.add(bookId);

  @override
  Future<void> markFinished(int bookId) async => finished.add(bookId);

  @override
  Future<void> addReadingTime(
    int bookId,
    int seconds, {
    required DateTime at,
    ReadingSpan? span,
  }) async {
    readingSeconds += seconds;
    if (span != null) spans.add(span);
  }
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
          AiBook? book,
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

  /// Bedahin belum dipake layar mana pun (provider-nya di #62).
  @override
  Stream<String> breakdownStream({
    required String? apiKey,
    required String model,
    required BreakdownInput input,
    CancelToken? cancel,
  }) => throw UnimplementedError();

  @override
  Future<AiReply> explain({
    required String? apiKey,
    required String model,
    AiBook? book,
    required List<String> context,
    required List<String> target,
    int attempts = 2,
  }) async {
    calls.add((
      apiKey: apiKey,
      model: model,
      book: book,
      context: context,
      target: target,
    ));
    if (apiKey == null) throw const AiException(AiError.noApiKey);
    if (failure != null) throw failure!;
    return AiReply(
      translations: [for (final t in target) 'id: $t'],
      meaning: 'Maknanya: ${target.length} paragraf.',
    );
  }

  /// Kalau diisi, explainStream ngalirin potongan dari sini (test yang
  /// ngatur jalannya stream). Kalau nggak, jawaban bersection lengkap
  /// sekaligus, isinya sama kayak [explain]. Sengaja bukan `async*`: error
  /// lewat `yield*` gak pernah nyampe di bawah `fakeAsync`.
  StreamController<String>? stream;
  final streamCalls = <List<String>>[];
  final streamBooks = <AiBook?>[];
  CancelToken? lastCancel;

  @override
  Stream<String> explainStream({
    required String? apiKey,
    required String model,
    AiBook? book,
    required List<String> context,
    required List<String> target,
    CancelToken? cancel,
  }) {
    streamCalls.add(target);
    streamBooks.add(book);
    lastCancel = cancel;
    if (apiKey == null) {
      return Stream.error(const AiException(AiError.noApiKey));
    }
    if (failure != null) return Stream.error(failure!);
    return stream?.stream ??
        Stream.value(
          [
            for (final (i, t) in target.indexed) '[T${i + 1}]\nid: $t',
            '[MAKNA]\nMaknanya: ${target.length} paragraf.',
          ].join('\n'),
        );
  }
}
