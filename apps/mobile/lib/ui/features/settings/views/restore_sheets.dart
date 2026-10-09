import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../data/services/restore_service.dart';
import '../../../../domain/models/backup.dart';
import '../../../core/format.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/edge_fade.dart';
import '../../../core/widgets/sheet.dart';
import 'backup_sheet.dart';

/// Ringkasan & konfirmasi (board 28). true = "Ganti & pulihin".
Future<bool> showRestoreSummary(
  BuildContext context, {
  required RestorePreview preview,
  required int currentBooks,
}) async =>
    await showAppSheet<bool>(
      context,
      maxHeight: 0.85,
      builder: (_) => _Summary(preview: preview, currentBooks: currentBooks),
    ) ??
    false;

class _Summary extends StatefulWidget {
  const _Summary({required this.preview, required this.currentBooks});

  final RestorePreview preview;
  final int currentBooks;

  @override
  State<_Summary> createState() => _SummaryState();
}

class _SummaryState extends State<_Summary> {
  bool _understood = false;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final m = widget.preview.manifest;
    void close(bool ok) => Navigator.of(context).pop(ok);
    return Padding(
      padding: Layout.sheetPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          const SheetGrabber(),
          Row(
            spacing: Space.s3,
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Pulihin dari backup ini?',
                    style: StabiloType.titleMd,
                  ),
                ),
              ),
              CircleButton(
                semanticLabel: 'Tutup',
                icon: AppIcons.close,
                onPressed: () => close(false),
              ),
            ],
          ),
          Flexible(
            child: EdgeFadeScroll(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 14,
                  children: [
                    _BackupInfo(name: widget.preview.fileName, manifest: m),
                    _Warning(currentBooks: widget.currentBooks),
                    _Check(
                      value: _understood,
                      onChanged: (v) => setState(() => _understood = v),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            spacing: 10,
            children: [
              AppButton.secondary(
                label: 'Batal',
                onPressed: () => close(false),
              ),
              Expanded(
                child: AppButton.danger(
                  label: 'Ganti & pulihin',
                  height: 52,
                  onPressed: _understood ? () => close(true) : null,
                ),
              ),
            ],
          ),
          Center(
            child: Text(
              'API key lo gak kesentuh.',
              style: StabiloType.caption.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w400,
                color: c.ink2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupInfo extends StatelessWidget {
  const _BackupInfo({required this.name, required this.manifest});

  final String name;
  final BackupManifest manifest;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    Widget stat(int n, String label) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(Space.s3),
        decoration: BoxDecoration(
          color: c.sheet,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 2,
          children: [
            Text(
              thousands(n),
              style: StabiloType.titleMd.copyWith(
                fontSize: 26,
                letterSpacing: -0.52,
                color: c.ink,
              ),
            ),
            Text(label, style: StabiloType.caption.copyWith(color: c.ink2)),
          ],
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(Radii.menu),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          Row(
            spacing: Space.s3,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: c.sheet,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Center(
                  child: AppIcon(AppIcons.restore, size: 22, color: c.ink),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StabiloType.mono.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      'Dibikin ${dateTime(manifest.createdAt)} · '
                      'Luma ${manifest.appVersion}',
                      style: StabiloType.caption.copyWith(color: c.ink2),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Row(
            spacing: Space.s2,
            children: [
              stat(manifest.books, 'buku di rak'),
              // Manifest ngitung grup yang udah diterjemahin.
              stat(manifest.aiResults, 'terjemahan'),
            ],
          ),
        ],
      ),
    );
  }
}

/// WarningBox (board Komponen 04).
class _Warning extends StatelessWidget {
  const _Warning({required this.currentBooks});

  final int currentBooks;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.dangerSoft,
          borderRadius: BorderRadius.circular(Radii.menu),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.s3,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: AppIcon(AppIcons.alert, size: 22, color: c.danger),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.s1,
                children: [
                  Text(
                    'Semua data di HP ini bakal diganti',
                    style: StabiloType.label.copyWith(color: c.dangerInk),
                  ),
                  Text(
                    'Buku, progres, sama terjemahan yang ada sekarang '
                    '(${thousands(currentBooks)} buku) diganti total sama isi '
                    'backup. Yang sekarang gak bisa dibalikin.',
                    style: StabiloType.caption.copyWith(
                      fontSize: 13.5,
                      height: 1.45,
                      fontWeight: FontWeight.w400,
                      color: c.ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ConfirmCheck: tombol danger baru aktif kalau dicentang.
class _Check extends StatelessWidget {
  const _Check({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      checked: value,
      label: 'Iya, gua ngerti. Ganti aja semuanya.',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Layout.touch),
          child: Row(
            spacing: Space.s3,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: value ? c.danger : null,
                  borderRadius: BorderRadius.circular(7),
                  border: value
                      ? null
                      : Border.all(color: c.fieldLine, width: Layout.outline),
                ),
                child: value
                    ? Center(
                        child: AppIcon(
                          AppIcons.check,
                          size: 14,
                          color: c.onDanger,
                        ),
                      )
                    : null,
              ),
              Expanded(
                child: Text(
                  'Iya, gua ngerti. Ganti aja semuanya.',
                  style: StabiloType.label.copyWith(
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lagi mulihin (board 29). [stage]: 1 = buku, 2 = progres & terjemahan,
/// 3 = beres. Gak bisa dibatalin (lagi ganti data).
class RestoreProgressSheet extends StatelessWidget {
  const RestoreProgressSheet({
    super.key,
    required this.name,
    required this.books,
    required this.stage,
  });

  final String name;
  final int books;
  final ValueListenable<int> stage;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      label: 'Lagi mulihin',
      child: Padding(
        padding: Layout.sheetPadding,
        child: ValueListenableBuilder(
          valueListenable: stage,
          builder: (context, s, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.s4,
            children: [
              const SheetGrabber(),
              Row(
                spacing: Space.s3,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: c.muted,
                      borderRadius: BorderRadius.circular(Radii.field),
                    ),
                    child: Center(
                      child: AppIcon(AppIcons.restore, size: 22, color: c.ink),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            'Lagi mulihin data lo...',
                            style: StabiloType.titleSm.copyWith(fontSize: 21),
                          ),
                        ),
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: StabiloType.mono.copyWith(
                            fontSize: 12.5,
                            color: c.ink2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Row(
                spacing: Space.s3,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.full),
                      child: LinearProgressIndicator(
                        value: s / 3,
                        minHeight: 8,
                        backgroundColor: c.track,
                        color: c.progressFill,
                      ),
                    ),
                  ),
                  Text(
                    '${(s / 3 * 100).floor()}%',
                    style: StabiloType.caption.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 10,
                children: [
                  for (final (i, label) in [
                    'Cek file backup',
                    'Balikin ${thousands(books)} buku',
                    'Balikin progres & terjemahan',
                  ].indexed)
                    SheetStep(label: label, done: s > i, current: s == i),
                ],
              ),
              Center(
                child: Text(
                  'Jangan tutup Luma dulu ya, bentar doang kok.',
                  textAlign: TextAlign.center,
                  style: StabiloType.caption.copyWith(
                    fontWeight: FontWeight.w400,
                    height: 1.45,
                    color: c.ink2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kenapa gagal mulihin (board 31, 32). true = "Pilih file lain".
Future<bool> showRestoreFailed(
  BuildContext context, {
  required String fileName,
  RestoreException? error,
}) async =>
    await showAppSheet<bool>(
      context,
      builder: (_) => _Failed(fileName: fileName, error: error),
    ) ??
    false;

class _Failed extends StatelessWidget {
  const _Failed({required this.fileName, this.error});

  final String fileName;

  /// Null = gagal pas ganti data (udah dibalikin).
  final RestoreException? error;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final m = error?.manifest;
    final (icon, title, body, code) = switch (error?.error) {
      RestoreError.notBackup => (
        AppIcons.fileRemove,
        'Ini bukan backup Luma',
        'File backup Luma itu yang namanya luma-backup-…zip, hasil dari '
            'tombol "Backup sekarang". Coba cari lagi di file manager ya.',
        fileName,
      ),
      RestoreError.tooNew => (
        AppIcons.alertCircle,
        'Backup-nya dari Luma yang lebih baru',
        'File ini dibikin pake Luma ${m?.appVersion}, sedangkan yang '
            'keinstall masih $appVersion. Install Luma versi terbaru dulu, '
            'baru pulihin.',
        '$fileName · v${m?.appVersion}',
      ),
      RestoreError.corrupt => (
        AppIcons.fileRemove,
        'File backup-nya rusak',
        'Isinya gak kebaca, mungkin kepotong pas disimpen. Coba file backup '
            'yang lain.',
        fileName,
      ),
      null => (
        AppIcons.alertCircle,
        'Yah, gagal mulihin',
        'Ada yang error pas ganti data, semuanya udah dibalikin kayak semula.',
        fileName,
      ),
    };
    void close(bool again) => Navigator.of(context).pop(again);
    return Semantics(
      liveRegion: true,
      label: 'Gagal mulihin',
      child: SheetFrame(
        actions: [
          AppButton.secondary(label: 'Tutup', onPressed: () => close(false)),
          Expanded(
            child: AppButton.primary(
              label: 'Pilih file lain',
              onPressed: () => close(true),
            ),
          ),
        ],
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: c.pink,
                  borderRadius: BorderRadius.circular(Radii.menu),
                ),
                child: Center(child: AppIcon(icon, size: 26, color: c.onPink)),
              ),
              CircleButton(
                semanticLabel: 'Tutup',
                icon: AppIcons.close,
                onPressed: () => close(false),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.s2,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: StabiloType.titleMd),
              ),
              Text(
                body,
                style: StabiloType.body.copyWith(fontSize: 15.5, color: c.ink2),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.muted,
                borderRadius: BorderRadius.circular(Space.s2),
              ),
              child: Text(
                code,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: StabiloType.mono.copyWith(fontSize: 12, color: c.ink2),
              ),
            ),
          ),
          Text(
            'Tenang, data yang sekarang gak diapa-apain.',
            style: StabiloType.caption.copyWith(
              fontWeight: FontWeight.w400,
              color: c.ink2,
            ),
          ),
        ],
      ),
    );
  }
}
