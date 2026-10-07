import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/settings_repository.dart';
import '../../../../data/services/backup_service.dart';
import '../../../../data/services/share_service.dart';
import '../../../../domain/models/backup.dart';

/// Alur backup (board 26 lagi dibungkus, 27 berhasil).
sealed class BackupState {
  const BackupState();
}

class BackupIdle extends BackupState {
  const BackupIdle();
}

/// Lagi dibungkus. [name] & [manifest] null sampe DB-nya ke-snapshot.
class BackupRunning extends BackupState {
  const BackupRunning({
    this.name,
    this.manifest,
    this.stage = BackupStage.books,
    this.fraction = 0,
  });

  final String? name;
  final BackupManifest? manifest;
  final BackupStage stage;
  final double fraction;
}

class BackupDone extends BackupState {
  const BackupDone(this.backup);

  final LastBackup backup;
}

class BackupFailed extends BackupState {
  const BackupFailed();
}

class BackupController extends Notifier<BackupState> {
  Completer<void>? _cancel;
  bool _busy = false;

  @override
  BackupState build() => const BackupIdle();

  /// Bungkus → menu share iOS → kalau beneran disimpen, catet sebagai backup
  /// terakhir. Zip sementaranya selalu dibuang di akhir.
  Future<void> start() async {
    if (_busy) return;
    _busy = true;
    _cancel = Completer();
    state = const BackupRunning();
    BackupFile? file;
    try {
      file = await ref
          .read(backupServiceProvider)
          .export(
            cancel: _cancel!.future,
            onStart: (name, manifest) =>
                state = BackupRunning(name: name, manifest: manifest),
            onProgress: (stage, fraction) {
              if (state case BackupRunning(:final name, :final manifest)) {
                state = BackupRunning(
                  name: name,
                  manifest: manifest,
                  stage: stage,
                  fraction: fraction,
                );
              }
            },
          );
      if (file == null) {
        state = const BackupIdle(); // dibatalin
        return;
      }
      // Sheet progres ditutup dulu, baru menu share-nya muncul.
      state = const BackupIdle();
      if (!await ref.read(shareServiceProvider).shareFile(file.file)) return;
      final last = (at: DateTime.now(), name: file.name, size: file.size);
      await ref.read(settingsRepositoryProvider).saveLastBackup(last);
      state = BackupDone(last);
    } catch (_) {
      state = const BackupFailed();
    } finally {
      await file?.dispose();
      _busy = false;
    }
  }

  void cancel() {
    if (!(_cancel?.isCompleted ?? true)) _cancel!.complete();
  }

  /// Toast hasil udah ditampilin.
  void dismiss() => state = const BackupIdle();
}

final backupControllerProvider =
    NotifierProvider<BackupController, BackupState>(BackupController.new);
