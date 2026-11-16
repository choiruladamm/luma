import 'package:flutter/material.dart';
import 'package:luma/l10n/l10n.dart';

import '../../../../data/services/cloud_backup_service.dart';
import '../../../../data/services/restore_service.dart';
import '../../../core/format.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/sheet.dart';

/// Pilih snapshot cloud (belum ada board: pakai komponen yang ada). Snapshot
/// yang dipilih langsung di-download & dicek di sini. Hasil: [RestorePreview]
/// (lanjut ke ringkasan board 28), [RestoreException], atau null (ditutup).
Future<Object?> showCloudRestorePicker(
  BuildContext context, {
  required Future<List<CloudBackup>> Function() load,
  required Future<RestorePreview> Function(CloudBackup backup) prepare,
}) => showAppSheet<Object?>(
  context,
  builder: (_) => CloudRestorePicker(load: load, prepare: prepare),
);

class CloudRestorePicker extends StatefulWidget {
  const CloudRestorePicker({
    super.key,
    required this.load,
    required this.prepare,
  });

  final Future<List<CloudBackup>> Function() load;
  final Future<RestorePreview> Function(CloudBackup backup) prepare;

  @override
  State<CloudRestorePicker> createState() => _CloudRestorePickerState();
}

class _CloudRestorePickerState extends State<CloudRestorePicker> {
  late final Future<List<CloudBackup>> _list = widget.load();
  String? _busy;
  bool _failed = false;

  Future<void> _pick(CloudBackup backup) async {
    if (_busy != null) return;
    setState(() {
      _busy = backup.id;
      _failed = false;
    });
    try {
      final preview = await widget.prepare(backup);
      if (!mounted) return await preview.discard();
      Navigator.of(context).pop(preview);
    } on RestoreException catch (e) {
      if (mounted) Navigator.of(context).pop(e);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = null;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final l = context.l10n;
    final note = StabiloType.caption.copyWith(color: c.ink2, height: 1.45);
    return SheetFrame(
      title: l.cloudRestorePickTitle,
      children: [
        FutureBuilder(
          future: _list,
          builder: (context, snap) {
            if (snap.hasError) {
              return Text(l.cloudRestoreLoadFailed, style: note);
            }
            final list = snap.data;
            if (list == null) {
              return Center(
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: c.ink,
                  ),
                ),
              );
            }
            if (list.isEmpty) return Text(l.cloudRestoreEmpty, style: note);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.s2,
              children: [
                for (final b in list)
                  _Row(
                    backup: b,
                    busy: _busy == b.id,
                    onTap: _busy == null ? () => _pick(b) : null,
                  ),
                if (_failed)
                  Text(
                    l.cloudRestoreDownloadFailed,
                    style: note.copyWith(color: c.ink),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.backup, required this.busy, this.onTap});

  final CloudBackup backup;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final l = context.l10n;
    final locale = l.localeName;
    final now = DateTime.now();
    return Material(
      color: c.sheet,
      borderRadius: BorderRadius.circular(Radii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.s3),
          child: Row(
            spacing: Space.s3,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: c.muted,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Center(
                  child: AppIcon(
                    AppIcons.cloudDownload,
                    size: 22,
                    color: c.ink,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      lastSeen(backup.createdAt, now, locale: locale),
                      style: StabiloType.label.copyWith(
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      '${l.settingsBooksTranslations(backup.books, backup.aiResults)} · ${fileSize(backup.size, locale: locale)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StabiloType.caption.copyWith(color: c.ink2),
                    ),
                  ],
                ),
              ),
              if (busy)
                SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.ink,
                  ),
                )
              else
                AppIcon(AppIcons.chevron, size: 18, color: c.ink2),
            ],
          ),
        ),
      ),
    );
  }
}
