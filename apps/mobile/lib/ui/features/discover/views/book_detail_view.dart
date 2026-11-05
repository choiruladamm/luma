import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../../domain/catalog/catalog_row.dart';
import '../../../../domain/models/catalog.dart';
import '../../../../routing/router.dart';
import '../../../core/format.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/edge_fade.dart';
import '../../../core/widgets/tag.dart';
import '../../bookshelf/view_models/bookshelf_view_model.dart';
import '../view_models/book_detail_view_model.dart';
import '../view_models/discover_view_model.dart';
import '../view_models/download_queue_view_model.dart';
import 'catalog_cover.dart';
import 'discover_states.dart';

/// Detail buku (board 09 · Cari buku, layar 10–13). Di luar shell: bar tab
/// ke-hide. Kepala kuning langsung dari [book]; isi dari `fetchDetail`.
class BookDetailView extends ConsumerStatefulWidget {
  const BookDetailView({super.key, required this.book});

  final CatalogBook book;

  @override
  ConsumerState<BookDetailView> createState() => _BookDetailViewState();
}

class _BookDetailViewState extends ConsumerState<BookDetailView> {
  var _expanded = false;

  CatalogBook get book => widget.book;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final state = ref.watch(bookDetailProvider(book));
    final detail = switch (state) {
      DetailReady(:final detail) => detail,
      _ => null,
    };
    final author = book.authors.firstOrNull;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(book: book),
              Expanded(
                child: EdgeFadeScroll(
                  bottom: EdgeFadeSide.none,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      Layout.margin,
                      Space.s5,
                      Layout.margin,
                      140 + bottom,
                    ),
                    children: [
                      Row(
                        spacing: 10,
                        children: [
                          _Fact(
                            value: _year(detail?.issued) ?? '–',
                            label: 'Masuk Gutenberg',
                          ),
                          _Fact(
                            value: detail?.fileSize == null
                                ? '–'
                                : fileSize(detail!.fileSize!),
                            label: 'Ukuran',
                          ),
                          const _Fact(value: 'Inggris', label: 'Bahasa'),
                        ],
                      ),
                      const SizedBox(height: Space.s5),
                      ...switch (state) {
                        DetailLoading(slow: true) => [
                          DiscoverNotice(
                            icon: AppIcons.history,
                            title: 'Katalognya lagi lemot nih',
                            body:
                                'Udah 5 detik lebih. Tungguin bentar, atau '
                                'coba lagi.',
                            onRetry: ref
                                .read(bookDetailProvider(book).notifier)
                                .load,
                          ),
                          const SizedBox(height: Space.s4),
                          const SkeletonRows(),
                        ],
                        DetailLoading() => [const SkeletonRows()],
                        DetailFailed(failure: NetworkFailure.offline) => [
                          DiscoverEmpty(
                            icon: AppIcons.offline,
                            title: 'Lo lagi offline',
                            body:
                                'Nyari tetep jalan. Tapi daftar rame, detail '
                                'buku, sama unduhan butuh internet. Buku di '
                                'rak tetap bisa lo baca kok.',
                            action: AppButton.primary(
                              label: 'Buka rak',
                              pill: true,
                              height: 48,
                              onPressed: () => context.go(Routes.home),
                            ),
                          ),
                        ],
                        DetailFailed() => [
                          DiscoverNotice(
                            icon: AppIcons.alert,
                            title: 'Katalog lagi gak bisa dihubungin',
                            body:
                                'Bukan salah lo kok. Coba lagi bentar lagi ya.',
                            onRetry: ref
                                .read(bookDetailProvider(book).notifier)
                                .load,
                          ),
                        ],
                        DetailReady(:final detail) => [
                          _Section(
                            title: 'Sinopsis',
                            gap: Space.s2,
                            child: detail.summary == null
                                ? Text(
                                    'Belum ada sinopsis buat buku ini. '
                                    'Langsung buka bab 1 aja.',
                                    style: StabiloType.body.copyWith(
                                      color: c.ink2,
                                    ),
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    spacing: Space.s2,
                                    children: [
                                      Text(
                                        detail.summary!,
                                        maxLines: _expanded ? null : 4,
                                        overflow: _expanded
                                            ? null
                                            : TextOverflow.ellipsis,
                                        style: StabiloType.body.copyWith(
                                          height: 1.55,
                                        ),
                                      ),
                                      if (!_expanded)
                                        Semantics(
                                          button: true,
                                          child: GestureDetector(
                                            onTap: () => setState(
                                              () => _expanded = true,
                                            ),
                                            child: Text(
                                              'Baca selengkapnya',
                                              style: StabiloType.label.copyWith(
                                                fontSize: 14,
                                                decoration:
                                                    TextDecoration.underline,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                          if (detail.subjects.isNotEmpty)
                            _Section(
                              title: 'Tentang',
                              child: _Chips([
                                for (final s in detail.subjects)
                                  s.split(' -- ').first,
                              ], outline: true),
                            ),
                          if (detail.bookshelves.isNotEmpty)
                            _Section(
                              title: 'Masuk daftar',
                              child: _Chips([
                                for (final s in detail.bookshelves)
                                  s.replaceFirst('Category: ', ''),
                              ]),
                            ),
                        ],
                      },
                      if (author != null)
                        _Section(
                          title: 'Penulis',
                          child: _AuthorRow(author: author, book: book),
                        ),
                      _Section(
                        title: 'Info file',
                        gap: 2,
                        child: Column(
                          children: [
                            for (final (i, (k, v)) in [
                              ('Format', 'EPUB'),
                              (
                                'Ukuran',
                                detail?.fileSize == null
                                    ? '–'
                                    : fileSize(detail!.fileSize!),
                              ),
                              ('Hak cipta', 'Public domain di AS'),
                              ('ID katalog', '#${book.externalId}'),
                            ].indexed)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 11,
                                ),
                                decoration: i == 3
                                    ? null
                                    : BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(color: c.track),
                                        ),
                                      ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      k,
                                      style: StabiloType.body.copyWith(
                                        fontSize: 14.5,
                                        color: c.ink2,
                                      ),
                                    ),
                                    Text(
                                      v,
                                      style: StabiloType.body.copyWith(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _Actions(book: book, bottom: bottom),
          ),
        ],
      ),
    );
  }

  static String? _year(String? issued) =>
      issued == null || issued.length < 4 ? null : issued.substring(0, 4);
}

/// Kepala kuning: Balik + "Detail buku", cover 100 + judul (28 → 24 / 21
/// kalau panjang, maks 4 baris) rata bawah cover.
class _Header extends ConsumerWidget {
  const _Header({required this.book});

  final CatalogBook book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.stabilo;
    final inShelf = ref.watch(shelfBookIdProvider(book)).value != null;
    final title = book.title;
    final size = title.length > 40
        ? 21.0
        : title.length > 24
        ? 24.0
        : 28.0;
    final years = book.authors.firstOrNull?.years;
    return Container(
      padding: EdgeInsets.fromLTRB(
        Layout.margin,
        MediaQuery.paddingOf(context).top + 4,
        Layout.margin,
        22,
      ),
      decoration: BoxDecoration(
        color: c.accent,
        border: Border(
          bottom: BorderSide(color: c.accentBorder, width: Layout.outline),
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 14,
        children: [
          Row(
            spacing: 10,
            children: [
              CircleButton(
                semanticLabel: 'Balik',
                icon: AppIcons.back,
                onPressed: () => context.pop(),
              ),
              Text(
                'Detail buku',
                style: StabiloType.titleSm.copyWith(
                  fontSize: 20,
                  color: c.onAccent,
                ),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: Space.s4,
            children: [
              CatalogCover(book: book, width: 100),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 6,
                  children: [
                    if (inShelf)
                      Tag.status('Udah di rak', icon: AppIcons.check),
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: StabiloType.titleLg.copyWith(
                          fontSize: size,
                          height: 1.1,
                          color: c.onAccent,
                        ),
                      ),
                    ),
                    if (book.authorsLabel case final a?)
                      Text(
                        a,
                        style: StabiloType.caption.copyWith(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: c.onAccent,
                        ),
                      ),
                    if (years != null)
                      Text(
                        years,
                        style: StabiloType.caption.copyWith(color: c.onAccent),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.value, required this.label});

  final String value, label;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final b = Theme.of(context).brightness;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: c.sheet,
          borderRadius: BorderRadius.circular(Radii.menu),
          border: Border.all(color: c.outline, width: Layout.outline),
          boxShadow: Elevation.press(c, b),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 1,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: StabiloType.label.copyWith(fontSize: 18),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: StabiloType.caption.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.gap = 10});

  final String title;
  final Widget child;
  final double gap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.s5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: gap,
      children: [
        Text(title, style: StabiloType.titleXs.copyWith(fontSize: 17)),
        child,
      ],
    ),
  );
}

class _Chips extends StatelessWidget {
  const _Chips(this.labels, {this.outline = false});

  final List<String> labels;
  final bool outline;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final l in labels)
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: outline ? null : c.muted,
              borderRadius: BorderRadius.circular(15),
              border: outline
                  ? Border.all(color: c.track, width: Layout.outline)
                  : null,
            ),
            // Center(widthFactor: 1): Container beralignment tanpa lebar
            // melar sepenuh ruang, chip jadi selebar layar.
            child: Center(
              widthFactor: 1,
              child: Text(
                l,
                style: StabiloType.caption.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Baris penulis: inisial, nama, "1775–1817 · 6 buku lain di katalog".
/// Tap = balik ke cari dengan query nama penulis.
class _AuthorRow extends ConsumerWidget {
  const _AuthorRow({required this.author, required this.book});

  final CatalogAuthor author;
  final CatalogBook book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.stabilo;
    final others = ref.watch(authorBookCountProvider(author.name)).value;
    final name = author.displayName;
    final initials = name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    final sub = [
      ?author.years,
      if (others != null) '$others buku lain di katalog',
    ].join(' · ');
    return Semantics(
      button: true,
      label: 'Cari buku lain $name',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          ref.read(discoverProvider.notifier).setQuery(name);
          context.pop();
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          decoration: BoxDecoration(
            color: c.muted,
            borderRadius: BorderRadius.circular(Radii.menu),
          ),
          child: Row(
            spacing: Space.s3,
            children: [
              Container(
                width: Layout.touch,
                height: Layout.touch,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.pink,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.outline, width: Layout.outline),
                ),
                child: Text(
                  initials,
                  style: StabiloType.label.copyWith(
                    fontWeight: FontWeight.w800,
                    color: c.onPink,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 1,
                  children: [
                    Text(name, style: StabiloType.label),
                    if (sub.isNotEmpty)
                      Text(
                        sub,
                        style: StabiloType.caption.copyWith(color: c.ink2),
                      ),
                  ],
                ),
              ),
              AppIcon(AppIcons.chevron, size: 16, color: c.ink2),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tombol bawah (board 10–13): Ambil buku → Lagi diunduh… · Batal → Baca
/// sekarang; udah di rak: Lanjut baca · 3%; gagal: pita pink + Coba lagi.
class _Actions extends ConsumerWidget {
  const _Actions({required this.book, required this.bottom});

  final CatalogBook book;
  final double bottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.stabilo;
    final queue = ref.read(downloadQueueProvider.notifier);
    final item = ref.watch(
      downloadQueueProvider.select(
        (q) => q
            .where(
              (i) =>
                  i.book.sourceId == book.sourceId &&
                  i.book.externalId == book.externalId,
            )
            .firstOrNull,
      ),
    );
    // Udah di rak: dari rak, atau dari antrian yang baru kelar (rak nyusul).
    final readId =
        switch (item) {
          DownloadItem(
            status: DownloadStatus.done || DownloadStatus.duplicate,
            :final bookId,
          ) =>
            bookId,
          _ => null,
        } ??
        ref.watch(shelfBookIdProvider(book)).value;
    final progress = readId == null
        ? null
        : ref
              .watch(booksStreamProvider)
              .value
              ?.where((b) => b.id == readId)
              .firstOrNull
              ?.progress;

    Widget note(String text) => Text(
      text,
      textAlign: TextAlign.center,
      style: StabiloType.caption.copyWith(color: c.ink2),
    );
    final children = switch (item) {
      DownloadItem(status: DownloadStatus.failed) => [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: c.pink,
            borderRadius: BorderRadius.circular(Radii.field),
          ),
          child: Row(
            spacing: 10,
            children: [
              AppIcon(AppIcons.alert, size: 18, color: c.onPink),
              Expanded(
                child: Text(
                  'Gagal ngunduh, koneksinya putus.',
                  style: StabiloType.caption.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.onPink,
                  ),
                ),
              ),
            ],
          ),
        ),
        AppButton.primary(
          label: 'Coba lagi',
          icon: AppIcons.retry,
          height: 56,
          onPressed: () => queue.enqueue(book),
        ),
      ],
      DownloadItem(status: DownloadStatus.done || DownloadStatus.duplicate) ||
      null when readId != null => [
        AppButton.primary(
          label: progress == null || progress == 0
              ? 'Baca sekarang'
              : 'Lanjut baca · ${(progress * 100).round()}%',
          height: 56,
          onPressed: () => context.push(Routes.reader(readId)),
        ),
        note('Udah ada di rak lo, gak perlu diunduh lagi'),
      ],
      DownloadItem(:final status, :final progress)
          when status == DownloadStatus.queued ||
              status == DownloadStatus.downloading ||
              status == DownloadStatus.importing =>
        [
          _Progress(
            label: switch (status) {
              DownloadStatus.queued => 'Antri…',
              DownloadStatus.importing => 'Nyusun buku…',
              _ => 'Lagi diunduh…',
            },
            progress: status == DownloadStatus.queued
                ? 0
                : progress.clamp(0.0, 1.0),
            onCancel: () => queue.cancel(item.key),
          ),
          note('Boleh ditinggal, nanti gua kabarin pas udah masuk rak.'),
        ],
      _ => [
        AppButton.primary(
          label: 'Ambil buku',
          icon: HugeIcons.strokeRoundedDownload04,
          height: 56,
          onPressed: () => queue.enqueue(book),
        ),
        note('Gratis, langsung masuk Rak buku lo'),
      ],
    };
    return Container(
      padding: EdgeInsets.fromLTRB(
        Layout.margin,
        Space.s4,
        Layout.margin,
        bottom + Space.s4,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: const Alignment(0, -0.6),
          colors: [c.canvas.withValues(alpha: 0), c.canvas],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: children,
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({
    required this.label,
    required this.progress,
    required this.onCancel,
  });

  final String label;
  final double progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      liveRegion: true,
      child: Container(
        height: 56,
        padding: const EdgeInsets.only(left: 16, right: 6),
        decoration: BoxDecoration(
          color: c.sheet,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: c.outline, width: Layout.outline),
        ),
        child: Row(
          spacing: Space.s3,
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 6,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        label,
                        style: StabiloType.label.copyWith(fontSize: 14),
                      ),
                      Text(
                        '${(progress * 100).round()}%',
                        style: StabiloType.label.copyWith(fontSize: 14),
                      ),
                    ],
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      color: c.ink,
                      backgroundColor: c.track,
                    ),
                  ),
                ],
              ),
            ),
            Semantics(
              button: true,
              child: GestureDetector(
                onTap: onCancel,
                child: Container(
                  height: Layout.touch,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: c.muted,
                    borderRadius: BorderRadius.circular(Radii.full),
                  ),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      'Batal',
                      style: StabiloType.label.copyWith(fontSize: 14),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
