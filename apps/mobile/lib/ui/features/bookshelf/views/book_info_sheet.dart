import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/book.dart';
import '../../../core/format.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/book_card.dart';
import '../../../core/widgets/book_cover.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/sheet.dart';
import '../view_models/bookshelf_view_model.dart';

/// Board 21 Info buku: cover + judul + progres, daftar rincian, "Lanjut baca"
/// dan "Hapus dari rak".
class BookInfoSheet extends ConsumerWidget {
  const BookInfoSheet({
    super.key,
    required this.book,
    this.coverFile,
    required this.onRead,
    required this.onDelete,
  });

  final ShelfBook book;
  final File? coverFile;
  final VoidCallback onRead;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.stabilo;
    final info = ref.watch(bookInfoProvider(book.id)).value;
    final now = DateTime.now();
    final percent = bookSticker(
      progress: book.progress,
      opened: book.opened,
      finished: false,
    );
    final rows = [
      (
        'Lagi di',
        !book.opened
            ? 'Belum mulai'
            : book.finished
            ? 'Kelar dibaca'
            : 'Bab ${book.chapter} dari ${book.chapterCount}',
      ),
      (
        'Terakhir dibuka',
        info?.lastOpenedAt == null ? '—' : lastSeen(info!.lastOpenedAt!, now),
      ),
      ('Ditambah', info == null ? '—' : date(info.createdAt)),
      ('Paragraf diartiin', info == null ? '—' : thousands(info.translated)),
      (
        'Ukuran file',
        info?.fileBytes == null ? '—' : fileSize(info!.fileBytes!),
      ),
      ('Nama file', info?.fileName ?? '—'),
    ];

    return SheetFrame(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.s3 + 2,
          children: [
            BookCover(
              title: book.title,
              author: book.author,
              file: coverFile,
              width: 72,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: Space.s1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.s1,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: StabiloType.titleMd,
                      ),
                    ),
                    if (book.author != null)
                      Text(
                        book.author!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: StabiloType.body.copyWith(
                          fontSize: 15,
                          color: c.ink2,
                        ),
                      ),
                    const SizedBox(height: Space.s2),
                    Row(
                      spacing: Space.s2,
                      children: [
                        Expanded(child: _Bar(book.progress)),
                        Text(
                          book.finished ? '100%' : percent,
                          style: StabiloType.caption.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            CircleButton(
              semanticLabel: 'Tutup',
              icon: AppIcons.close,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s4,
            vertical: Space.s1,
          ),
          decoration: BoxDecoration(
            color: c.muted,
            borderRadius: BorderRadius.circular(Radii.menu),
          ),
          child: Column(
            children: [
              for (final (i, (k, v)) in rows.indexed)
                Container(
                  constraints: const BoxConstraints(minHeight: Layout.touch),
                  decoration: i == rows.length - 1
                      ? null
                      : BoxDecoration(
                          border: Border(bottom: BorderSide(color: c.track)),
                        ),
                  child: Row(
                    spacing: Space.s3,
                    children: [
                      Text(
                        k,
                        style: StabiloType.caption.copyWith(
                          fontSize: 14,
                          color: c.ink2,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          v,
                          textAlign: TextAlign.right,
                          style: StabiloType.caption.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Column(
          spacing: 6,
          children: [
            AppButton.primary(
              label: book.opened && !book.finished ? 'Lanjut baca' : 'Baca',
              onPressed: onRead,
            ),
            Semantics(
              button: true,
              child: InkWell(
                onTap: onDelete,
                borderRadius: BorderRadius.circular(Radii.full),
                child: SizedBox(
                  height: 48,
                  child: Center(
                    child: Text(
                      'Hapus dari rak',
                      style: StabiloType.label.copyWith(color: c.danger),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar(this.progress);

  final double progress;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: progress.clamp(0, 1),
        minHeight: 8,
        backgroundColor: c.track,
        color: c.progressFill,
      ),
    );
  }
}
