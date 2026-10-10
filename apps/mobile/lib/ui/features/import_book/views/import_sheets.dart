import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../../data/repositories/import_repository.dart';
import '../../../../data/services/epub_parser.dart';
import '../../../../data/services/file_storage.dart';
import '../../../../domain/luma_markdown.dart';
import '../../../../domain/models/book.dart';
import '../../../core/format.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/book_cover.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/sheet.dart';
import '../view_models/import_view_model.dart';

/// Board 13: "Lagi ngebongkar EPUB...". Ditutup sama listener di rak begitu
/// state-nya bukan [ImportProcessing] lagi.
class ImportProgressSheet extends ConsumerWidget {
  const ImportProgressSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.stabilo;
    final state = ref.watch(importControllerProvider);
    if (state is! ImportProcessing) return const SizedBox.shrink();
    final outlineDone = state.stage.index > ImportStage.outline.index;

    return Semantics(
      label: 'Lagi import',
      child: SheetFrame(
        children: [
          Row(
            spacing: Space.s3,
            children: [
              _Tile(
                color: c.muted,
                size: 48,
                child: AppIcon(
                  HugeIcons.strokeRoundedFile01,
                  size: 22,
                  color: c.ink,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text('Lagi ngebongkar EPUB...', style: StabiloType.titleMd),
                    Text(
                      '${state.fileName} · ${fileSize(state.size)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StabiloType.mono.copyWith(
                        fontSize: 13,
                        color: c.ink2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Angka + bar nyusul dari nilai sebelumnya; "Kurangi gerakan" nyala =
          // loncat langsung, persen tetep muncul.
          Semantics(
            value: '${(state.progress * 100).round()}%',
            child: ExcludeSemantics(
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: state.progress),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : state.glide,
                curve: Curves.easeOut,
                builder: (_, value, _) => Row(
                  spacing: Space.s3,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.full),
                        child: LinearProgressIndicator(
                          value: value,
                          minHeight: 8,
                          backgroundColor: c.track,
                          color: c.progressFill,
                        ),
                      ),
                    ),
                    Text(
                      '${(value * 100).round()}%',
                      style: StabiloType.caption.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Column(
            spacing: 10,
            children: [
              _Step(
                'Baca judul & penulis',
                done: outlineDone,
                active: !outlineDone,
              ),
              _Step('Ambil cover', done: outlineDone, active: false),
              _Step(
                'Mecah per bab & paragraf',
                done: false,
                active: outlineDone,
              ),
            ],
          ),
          const SizedBox(height: Space.s2),
          AppButton.secondary(
            label: 'Batalin',
            onPressed: () =>
                ref.read(importControllerProvider.notifier).cancel(),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.label, {required this.done, required this.active});

  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Row(
      spacing: 10,
      children: [
        SizedBox.square(
          dimension: 22,
          child: done
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.muted,
                    shape: BoxShape.circle,
                  ),
                  // Center: tanpa ini ikon dipaksa tight 22×22 sama SizedBox.
                  child: Center(
                    child: AppIcon(AppIcons.check, size: 12, color: c.ink),
                  ),
                )
              : active
              ? const Center(child: _PulseDot())
              : DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: c.track, width: Layout.outline),
                  ),
                ),
        ),
        Expanded(
          child: Text(
            label,
            style: StabiloType.label.copyWith(
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              color: active || done ? c.ink : c.ink2,
            ),
          ),
        ),
      ],
    );
  }
}

/// Titik "lagi jalan" yang denyut. Diem kalau iOS "Kurangi gerakan" nyala.
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: Motion.thinkingDots,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final curve = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.5).animate(curve),
      child: ScaleTransition(
        scale: Tween(begin: 1.0, end: 0.6).animate(curve),
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: c.accent,
            shape: BoxShape.circle,
            border: Border.all(color: c.accentBorder, width: Layout.outline),
          ),
        ),
      ),
    );
  }
}

/// Board 15: buku yang sama udah ada di rak.
class ImportDuplicateSheet extends ConsumerWidget {
  const ImportDuplicateSheet({
    super.key,
    required this.book,
    required this.onOpen,
    required this.onPickAnother,
  });

  final ShelfBook book;
  final VoidCallback onOpen;
  final VoidCallback onPickAnother;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.stabilo;
    final meta = [
      ?book.author,
      'ditambah ${ago(book.createdAt, DateTime.now())}',
    ].join(' · ');
    return SheetFrame(
      children: [
        _Heading(
          'Eh, buku ini udah ada di rak',
          'Lo pernah import buku yang sama. Mau lanjutin yang lama aja?',
        ),
        Container(
          padding: const EdgeInsets.all(Space.s3),
          decoration: BoxDecoration(
            color: c.muted,
            borderRadius: BorderRadius.circular(Radii.menu),
          ),
          child: Row(
            spacing: 14,
            children: [
              BookCover(
                title: book.title,
                author: book.author,
                width: 52,
                file: book.coverName == null
                    ? null
                    : ref.read(fileStorageProvider).cover(book.coverName!),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 6,
                  children: [
                    Text(book.title, style: StabiloType.titleSm),
                    Text(
                      meta,
                      style: StabiloType.caption.copyWith(color: c.ink2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        AppButton.primary(label: 'Buka yang udah ada', onPressed: onOpen),
        Row(
          spacing: Space.s2,
          children: [
            Expanded(
              child: AppButton.secondary(
                label: 'Ganti file-nya',
                height: 48,
                onPressed: onPickAnother,
              ),
            ),
            Expanded(
              child: AppButton.secondary(
                label: 'Batal',
                height: 48,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
        Text(
          'Ganti file = progres & terjemahan lama tetep aman.',
          textAlign: TextAlign.center,
          style: StabiloType.caption.copyWith(color: c.ink2),
        ),
      ],
    );
  }
}

/// Board 16–18: file rusak, bukan EPUB, atau dikunci DRM.
class ImportFailedSheet extends StatelessWidget {
  const ImportFailedSheet({
    super.key,
    required this.fileName,
    required this.error,
    required this.onPickAnother,
  });

  final String fileName;
  final EpubError error;
  final VoidCallback onPickAnother;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final (icon, title, body, code) = switch (error) {
      EpubError.corrupt => (
        HugeIcons.strokeRoundedFileCorrupt,
        'File-nya rusak nih',
        'EPUB-nya gak bisa dibuka, kayaknya korup atau kedownload setengah. '
            'Coba download ulang, terus import lagi.',
        '$fileName · file rusak',
      ),
      EpubError.notEpub => (
        HugeIcons.strokeRoundedFileRemove,
        'Ini bukan EPUB',
        'App ini cuma bisa baca .epub. Kalau bukunya PDF atau MOBI, convert '
            'dulu ke EPUB (misal pake Calibre), baru import lagi.',
        fileName,
      ),
      EpubError.drm => (
        HugeIcons.strokeRoundedSquareLock02,
        'Bukunya dikunci DRM',
        'EPUB ini dikunci sama tokonya, jadi cuma bisa dibaca di app toko itu. '
            'Pake file EPUB yang bebas DRM ya.',
        '$fileName · DRM',
      ),
    };
    return Semantics(
      liveRegion: true,
      child: SheetFrame(
        actions: [
          AppButton.secondary(
            label: 'Tutup',
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: AppButton.primary(
              label: 'Pilih file lain',
              onPressed: onPickAnother,
            ),
          ),
        ],
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Tile(
                color: c.pink,
                size: 52,
                radius: Radii.menu,
                child: AppIcon(icon, size: 26, color: c.onPink),
              ),
              const Spacer(),
              CircleButton(
                semanticLabel: 'Tutup',
                icon: AppIcons.close,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          _Heading(title, body),
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
        ],
      ),
    );
  }
}

/// Board Import Markdown 6a–6d: file kosong, header salah, atau gak kebaca.
class ImportMarkdownFailedSheet extends StatelessWidget {
  const ImportMarkdownFailedSheet({
    super.key,
    required this.failed,
    required this.onRetry,
  });

  final ImportMarkdownFailed failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final copy = failed.copy;
    final empty = failed.error == LumaMarkdownError.empty;
    return Semantics(
      liveRegion: true,
      child: SheetFrame(
        actions: [
          AppButton.secondary(
            label: 'Tutup',
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: AppButton.primary(label: 'Coba lagi', onPressed: onRetry),
          ),
        ],
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Tile(
                color: c.pink,
                size: 52,
                radius: Radii.menu,
                child: AppIcon(
                  empty
                      ? HugeIcons.strokeRoundedFileRemove
                      : HugeIcons.strokeRoundedFileCorrupt,
                  size: 26,
                  color: c.onPink,
                ),
              ),
              const Spacer(),
              CircleButton(
                semanticLabel: 'Tutup',
                icon: AppIcons.close,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          _Heading(copy.title, copy.body),
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
                copy.chip,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: StabiloType.mono.copyWith(fontSize: 12, color: c.ink2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, this.body);

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.s2,
      children: [
        Semantics(header: true, child: Text(title, style: StabiloType.titleMd)),
        Text(
          body,
          style: StabiloType.readingSheet.copyWith(
            fontFamily: StabiloType.ui,
            color: context.stabilo.ink2,
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.color,
    required this.size,
    required this.child,
    this.radius = Space.s4,
  });

  final Color color;
  final double size;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: child,
  );
}
