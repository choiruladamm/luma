import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/cloud_backup_repository.dart';
import '../../../../data/repositories/settings_repository.dart';
import '../../../../data/services/backend_client.dart';
import '../../../../data/services/backup_service.dart';
import '../../../../data/services/share_service.dart';
import '../../../../domain/models/backup.dart';

/// Backup flow (board 26 packing, 27 success).
sealed class BackupState {
  const BackupState();
}

class BackupIdle extends BackupState {
  const BackupIdle();
}

/// Packing. [name] & [manifest] are null until the DB is snapshotted. [cloud] =
/// uploaded to the account (can't be cancelled, no share menu).
class BackupRunning extends BackupState {
  const BackupRunning({
    this.name,
    this.manifest,
    this.stage = BackupStage.books,
    this.fraction = 0,
    this.cloud = false,
  });

  final String? name;
  final BackupManifest? manifest;
  final BackupStage stage;
  final double fraction;
  final bool cloud;
}

class BackupDone extends BackupState {
  const BackupDone(this.backup);

  final LastBackup backup;
}

class BackupFailed extends BackupState {
  const BackupFailed({this.storageFull = false});

  /// Cloud quota exhausted (`STORAGE_FULL`).
  final bool storageFull;
}

class BackupController extends Notifier<BackupState> {
  Completer<void>? _cancel;
  bool _busy = false;

  @override
  BackupState build() => const BackupIdle();

  /// Pack → share menu → if actually saved, record as the last backup. The
  /// temporary zip is always discarded at the end.
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
        state = const BackupIdle(); // cancelled
        return;
      }
      // The progress sheet closes first, then the share menu appears.
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

  /// Cloud backup (docs/backup.md): DB snapshot + files not yet in the cloud.
  /// The result goes through the same toast as a regular backup.
  Future<void> startCloud() async {
    if (_busy) return;
    _busy = true;
    state = const BackupRunning(cloud: true);
    try {
      final last = await ref
          .read(cloudBackupRepositoryProvider)
          .backup(
            onStart: (name, manifest) => state = BackupRunning(
              name: name,
              manifest: manifest,
              cloud: true,
            ),
            onProgress: (stage, fraction) {
              if (state case BackupRunning(:final name, :final manifest)) {
                state = BackupRunning(
                  name: name,
                  manifest: manifest,
                  stage: stage,
                  fraction: fraction,
                  cloud: true,
                );
              }
            },
          );
      state = BackupDone(last);
    } on BackendException catch (e) {
      state = BackupFailed(storageFull: e.code == 'STORAGE_FULL');
    } catch (_) {
      state = const BackupFailed();
    } finally {
      _busy = false;
    }
  }

  void cancel() {
    if (!(_cancel?.isCompleted ?? true)) _cancel!.complete();
  }

  /// The result toast has been shown.
  void dismiss() => state = const BackupIdle();
}

final backupControllerProvider =
    NotifierProvider<BackupController, BackupState>(BackupController.new);
