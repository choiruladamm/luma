import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/import_repository.dart';
import 'package:luma/data/services/epub_parser.dart';
import 'package:luma/data/services/file_picker_service.dart';
import 'package:luma/data/services/file_storage.dart';
import 'package:luma/ui/features/import_book/view_models/import_view_model.dart';

class FakePicker extends FilePickerService {
  PickedFile? next;
  @override
  Future<PickedFile?> pickEpub() async => next;
}

PickedFile picked(String name, Uint8List bytes) =>
    PickedFile(name: name, size: bytes.length, read: () async => bytes);

// Plain test(): the real event loop drives Drift and the parse isolates.
void main() {
  final epub = File('test/fixtures/enchiridion.epub').readAsBytesSync();
  late AppDatabase db;
  late Directory root;
  late FakePicker picker;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    root = await Directory.systemTemp.createTemp('luma_import_ui_');
    final storage = FileStorage(root);
    await storage.ensureDirs();
    picker = FakePicker();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        fileStorageProvider.overrideWithValue(storage),
        filePickerServiceProvider.overrideWithValue(picker),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
    await root.delete(recursive: true);
  });

  ImportController controller() =>
      container.read(importControllerProvider.notifier);
  ImportState state() => container.read(importControllerProvider);

  test('pick → processing stages → success with the new book', () async {
    final seen = <ImportStage>[];
    container.listen(importControllerProvider, (_, s) {
      if (s is ImportProcessing) seen.add(s.stage);
    }, fireImmediately: true);

    picker.next = picked('pg45109-images-3.epub', epub);
    await controller().pick();

    expect(seen.toSet(), ImportStage.values.toSet());
    final s = state();
    expect(s, isA<ImportSuccess>());
    expect((s as ImportSuccess).book.title, 'The Enchiridion');
  });

  test('cancelling the picker does nothing', () async {
    await controller().pick();
    expect(state(), isA<ImportIdle>());
  });

  test('the same file twice → duplicate pointing at the first book', () async {
    picker.next = picked('a.epub', epub);
    await controller().pick();
    final first = (state() as ImportSuccess).book.id;
    await controller().pick();
    expect((state() as ImportDuplicate).book.id, first);
  });

  test('bad files → failed with the right reason', () async {
    for (final (name, bytes, error) in [
      ('notes.pdf', epub, EpubError.notEpub),
      ('junk.epub', Uint8List.fromList([1, 2, 3]), EpubError.notEpub),
      (
        'cut.epub',
        Uint8List.sublistView(epub, 0, epub.length ~/ 2),
        EpubError.corrupt,
      ),
    ]) {
      await controller().importFile(picked(name, bytes));
      final s = state() as ImportFailed;
      expect((s.fileName, s.error), (name, error));
    }
  });

  test('Batalin goes idle right away and nothing is imported', () async {
    final run = controller().importFile(picked('a.epub', epub));
    controller().cancel();
    expect(state(), isA<ImportIdle>());
    await run;
    expect(state(), isA<ImportIdle>());
    expect(await db.select(db.books).get(), isEmpty);
  });
}
