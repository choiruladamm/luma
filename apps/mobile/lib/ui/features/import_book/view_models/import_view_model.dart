import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/book_repository.dart';
import '../../../../data/repositories/import_repository.dart';
import '../../../../data/services/epub_parser.dart';
import '../../../../data/services/file_picker_service.dart';
import '../../../../domain/models/book.dart';

/// State alur import (board 13–18).
sealed class ImportState {
  const ImportState();
}

class ImportIdle extends ImportState {
  const ImportIdle();
}

class ImportProcessing extends ImportState {
  const ImportProcessing({
    required this.fileName,
    required this.size,
    required this.stage,
  });

  final String fileName;
  final int size;
  final ImportStage stage;
}

class ImportSuccess extends ImportState {
  const ImportSuccess(this.book);

  final ShelfBook book;
}

class ImportDuplicate extends ImportState {
  const ImportDuplicate(this.book);

  /// Buku yang udah ada di rak.
  final ShelfBook book;
}

class ImportFailed extends ImportState {
  const ImportFailed({required this.fileName, required this.error});

  final String fileName;
  final EpubError error;
}

class ImportController extends Notifier<ImportState> {
  bool _cancelled = false;

  @override
  ImportState build() => const ImportIdle();

  /// Buka file picker, terus import file yang dipilih.
  Future<void> pick() async {
    if (state is ImportProcessing) return;
    final file = await ref.read(filePickerServiceProvider).pickEpub();
    if (file != null) await importFile(file);
  }

  Future<void> importFile(PickedFile file) async {
    _cancelled = false;
    void stage(ImportStage s) => state = ImportProcessing(
      fileName: file.name,
      size: file.size,
      stage: s,
    );
    stage(ImportStage.reading);
    try {
      final result = await ref
          .read(importRepositoryProvider)
          .importEpub(
            await file.read(),
            fileName: file.name,
            onStage: (s) {
              if (!_cancelled) stage(s);
            },
            isCancelled: () => _cancelled,
          );
      // Batal pas lagi nyimpen: bukunya tetep masuk rak, sheet-nya udah tutup.
      if (_cancelled) return;
      final book = await ref.read(bookRepositoryProvider).book(result.bookId);
      state = book == null
          ? ImportFailed(fileName: file.name, error: EpubError.corrupt)
          : result.duplicate
          ? ImportDuplicate(book)
          : ImportSuccess(book);
    } on ImportCancelled {
      state = const ImportIdle();
    } on EpubException catch (e) {
      state = ImportFailed(fileName: file.name, error: e.error);
    } catch (_) {
      state = ImportFailed(fileName: file.name, error: EpubError.corrupt);
    }
  }

  /// "Batalin" di sheet proses.
  void cancel() {
    _cancelled = true;
    state = const ImportIdle();
  }

  /// Toast / sheet hasil udah ditutup.
  void dismiss() => state = const ImportIdle();
}

final importControllerProvider =
    NotifierProvider<ImportController, ImportState>(ImportController.new);
