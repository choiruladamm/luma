import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/book_repository.dart';
import '../../../../data/repositories/import_repository.dart';
import '../../../../data/services/epub_parser.dart';
import '../../../../data/services/file_picker_service.dart';
import '../../../../domain/models/book.dart';
import '../../../core/theme/stabilo_tokens.dart';

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
    this.progress = 0,
    this.glide = Motion.progressStep,
  });

  final String fileName;
  final int size;
  final ImportStage stage;

  /// 0–1, asli dari tahapnya, cuma naik. 1 = beres, tinggal nahan sampe batas
  /// minimum loading.
  final double progress;

  /// Lama angka + bar nyusul ke [progress]. Panjang kalau import kecepetan,
  /// biar naiknya halus sampe 100% pas batas minimum.
  final Duration glide;
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
  /// Naik tiap import baru / dibatalin; run yang nomornya ketinggalan = batal.
  int _run = 0;

  @override
  ImportState build() => const ImportIdle();

  /// Buka file picker, terus import file yang dipilih.
  Future<void> pick() async {
    if (state is ImportProcessing) return;
    final file = await ref.read(filePickerServiceProvider).pickEpub();
    if (file != null) await importFile(file);
  }

  Future<void> importFile(PickedFile file) async {
    final run = ++_run;
    bool cancelled() => run != _run;
    final clock = Stopwatch()..start();
    var stage = ImportStage.reading;
    var progress = 0.0;
    void show({Duration glide = Motion.progressStep}) =>
        state = ImportProcessing(
          fileName: file.name,
          size: file.size,
          stage: stage,
          progress: progress,
          glide: glide,
        );
    show();
    try {
      final result = await ref
          .read(importRepositoryProvider)
          .importEpub(
            await file.read(),
            fileName: file.name,
            onStage: (s) {
              if (cancelled()) return;
              stage = s;
              show();
            },
            onProgress: (p) {
              // Cuma naik, dan cuma update tiap ganti persen bulat.
              if (cancelled() || p <= progress) return;
              final wholePercent = (p * 100).floor() > (progress * 100).floor();
              progress = p;
              if (wholePercent) show();
            },
            isCancelled: cancelled,
          );
      // Batal pas lagi nyimpen: bukunya tetep masuk rak, sheet-nya udah tutup.
      if (cancelled()) return;
      final book = await ref.read(bookRepositoryProvider).book(result.bookId);
      if (cancelled()) return;
      if (book == null) {
        state = ImportFailed(fileName: file.name, error: EpubError.corrupt);
        return;
      }
      // Duplikat gak ditahan.
      if (result.duplicate) {
        state = ImportDuplicate(book);
        return;
      }
      // Import kecepetan: angka nyusul halus ke 100% sampe (batas minimum −
      // jeda), terus jeda, baru "berhasil". Import lambat: cuma nyusul
      // sebentar + jeda, gak ada tambahan nahan.
      final left = Motion.importMin - Motion.importSettle - clock.elapsed;
      final glide = left > Motion.progressStep ? left : Motion.progressStep;
      progress = 1;
      show(glide: glide);
      await Future<void>.delayed(glide + Motion.importSettle);
      if (cancelled()) return;
      state = ImportSuccess(book);
    } on ImportCancelled {
      // cancel() udah ngembaliin ke idle.
    } on EpubException catch (e) {
      if (!cancelled()) {
        state = ImportFailed(fileName: file.name, error: e.error);
      }
    } catch (_) {
      if (!cancelled()) {
        state = ImportFailed(fileName: file.name, error: EpubError.corrupt);
      }
    }
  }

  /// "Batalin" di sheet proses.
  void cancel() {
    _run++;
    state = const ImportIdle();
  }

  /// Toast / sheet hasil udah ditutup.
  void dismiss() => state = const ImportIdle();
}

final importControllerProvider =
    NotifierProvider<ImportController, ImportState>(ImportController.new);
