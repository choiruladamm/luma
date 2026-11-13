import 'package:luma/ui/core/book_copy.dart';
import 'package:luma/l10n/l10n.dart';

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../../data/repositories/book_repository.dart';
import '../../../../data/repositories/reading_progress_repository.dart';
import '../../../../data/repositories/settings_repository.dart';
import '../../../../data/services/file_storage.dart';
import '../../../../domain/models/backup.dart';
import '../../../../domain/models/book.dart';
import '../../../../domain/shelf_sort.dart';
import '../../../../routing/router.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/book_card.dart';
import '../../../core/widgets/book_row.dart';
import '../../../core/widgets/edge_fade.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/book_cover.dart';
import '../../../core/widgets/book_menu.dart';
import '../../../core/widgets/dialog.dart';
import '../../../core/widgets/menu.dart';
import '../../../core/widgets/sheet.dart';
import '../../../core/widgets/toast.dart';
import '../../import_book/view_models/import_view_model.dart';
import '../../import_book/views/import_markdown_sheet.dart';
import '../../import_book/views/import_sheets.dart';
import '../../settings/view_models/backup_view_model.dart';
import '../../settings/views/backup_listener.dart';
import '../../shell/view_models/tab_reselect.dart';
import '../../../core/widgets/nav_bar.dart';
import '../../discover/curated_books.dart';
import '../../discover/view_models/download_queue_view_model.dart';
import '../../discover/views/catalog_cover.dart';
import '../view_models/bookshelf_view_model.dart';
import '../../auth/view_models/auth_view_model.dart';
import '../../auth/views/session_banner.dart';
import 'backup_reminder.dart';
import 'book_info_sheet.dart';
import 'shelf_header.dart';
import 'continue_card.dart';

/// Rak buku (board 01 Rak kosong, 02 Rak) + alur import (board 13–18).
class BookshelfView extends ConsumerStatefulWidget {
  const BookshelfView({super.key});

  @override
  ConsumerState<BookshelfView> createState() => _BookshelfViewState();
}

class _BookshelfViewState extends ConsumerState<BookshelfView> {
  /// Sheet proses import lagi kebuka; ditutup dari sini (bukan dari sheet-nya
  /// sendiri) biar gak nutup sheet hasil yang baru dibuka.
  bool _progressOpen = false;

  /// Sheet "Masuk ke buku mana?" kebuka. Tetap kebuka pas dialog bab dobel
  /// nongol di atasnya; ditutup dari sini begitu import beres / gagal.
  bool _markdownSheetOpen = false;

  /// Id buku terbesar di rak pas import mulai. Buku baru (id lebih besar) udah
  /// masuk DB sebelum import "berhasil", tapi disembunyiin dulu: yang tampil
  /// cuma kartu proses.
  int? _importBaseline;

  ImportController get _import => ref.read(importControllerProvider.notifier);

  void _onImport(ImportState? prev, ImportState next) {
    // Sheet dibuka di navigator root (di atas bar tab), tutupnya juga dari sana.
    final root = Navigator.of(context, rootNavigator: true);
    if (next is! ImportProcessing && _progressOpen) {
      _progressOpen = false;
      root.pop();
    }
    if (_markdownSheetOpen &&
        (next is ImportMarkdownDone || next is ImportMarkdownFailed)) {
      _markdownSheetOpen = false;
      // Sheet + dialog bab dobel (kalau ada) turun bareng.
      root.popUntil((r) => r is! PopupRoute);
    }
    switch (next) {
      case ImportProcessing() when !_progressOpen:
        _progressOpen = true;
        _importBaseline = ref
            .read(booksStreamProvider)
            .value
            ?.fold<int>(0, (m, b) => b.id > m ? b.id : m);
        showAppSheet<void>(
          context,
          dismissible: false,
          builder: (_) => const ImportProgressSheet(),
        );
      case ImportSuccess(:final book, :final skippedPages):
        _import.dismiss();
        showToast(
          context,
          context.l10n.bookshelfAddedToYourShelf,
          // PDF campuran: jujur soal halaman tanpa teks yang dilewati.
          subtitle: skippedPages > 0
              ? '${book.title} · ${context.l10n.importPdfSkippedPages(skippedPages)}'
              : [book.title, ?book.author].join(' · '),
          duration: skippedPages > 0 ? Motion.toastBaca : null,
          leading: BookCover(
            title: book.title,
            width: 30,
            file: _cover(book.coverName),
          ),
          actionLabel: context.l10n.downloadRead,
          onAction: () => context.push(Routes.reader(book.id)),
        );
      case ImportDuplicate(:final book):
        showAppSheet<void>(
          context,
          builder: (sheet) => ImportDuplicateSheet(
            book: book,
            onOpen: () {
              Navigator.of(sheet).pop();
              context.push(Routes.reader(book.id));
            },
            onPickAnother: () {
              Navigator.of(sheet).pop();
              _import.pick();
            },
          ),
        ).whenComplete(_dismissIf(next));
      case ImportFailed(:final fileName, :final error):
        showAppSheet<void>(
          context,
          builder: (sheet) => ImportFailedSheet(
            fileName: fileName,
            error: error,
            onPickAnother: () {
              Navigator.of(sheet).pop();
              _import.pick();
            },
          ),
        ).whenComplete(_dismissIf(next));
      case ImportPdfFailed(:final fileName, :final error):
        showAppSheet<void>(
          context,
          builder: (sheet) => ImportPdfFailedSheet(
            fileName: fileName,
            error: error,
            onPickAnother: () {
              Navigator.of(sheet).pop();
              _import.pick();
            },
          ),
        ).whenComplete(_dismissIf(next));
      case final ImportMarkdownAsk ask when prev is! ImportMarkdownPending:
        _markdownSheetOpen = true;
        showAppSheet<void>(
          context,
          maxHeight: Layout.pickSheetHeight,
          builder: (_) => ImportMarkdownSheet(ask: ask),
        ).whenComplete(() {
          _markdownSheetOpen = false;
          if (ref.read(importControllerProvider) is ImportMarkdownPending) {
            _import.dismiss();
          }
        });
      case ImportMarkdownConflict(:final chapter):
        showConfirmDialog(
          context,
          title: context.l10n.bookshelfChapterAlreadyExists(chapter),
          message: context.l10n.bookshelfReplacingChapterWillAlsoDeleteIts(
            chapter,
          ),
          confirmLabel: context.l10n.bookshelfReplace,
          icon: AppIcons.retry,
          onConfirm: _import.confirmReplace,
        ).then((ok) {
          if (!ok) _import.cancelReplace();
        });
      case ImportMarkdownDone(
        :final book,
        :final chapter,
        :final chapterId,
        :final created,
      ):
        _import.dismiss();
        showToast(
          context,
          created
              ? context.l10n.bookshelfAddedToShelf(book.title)
              : context.l10n.bookshelfChapterAddedTo(chapter, book.title),
          leading: BookCover(
            title: book.title,
            width: 30,
            file: _cover(book.coverName),
          ),
          actionLabel: context.l10n.downloadRead,
          duration: Motion.toastBaca,
          onAction: () => _readChapter(book.id, chapterId),
        );
      case final ImportMarkdownFailed failed:
        showAppSheet<void>(
          context,
          builder: (sheet) => ImportMarkdownFailedSheet(
            failed: failed,
            onRetry: () {
              Navigator.of(sheet).pop();
              _import.pick();
            },
          ),
        ).whenComplete(_dismissIf(next));
      default:
    }
  }

  /// "Baca" di toast: buka bab yang barusan masuk. Posisi baca pindah ke
  /// awal bab itu, cuma karena user sendiri yang tap.
  Future<void> _readChapter(int bookId, int chapterId) async {
    await ref.read(readingProgressRepositoryProvider).save(bookId, (
      chapterId: chapterId,
      paragraphIndex: 0,
      paragraphOffset: 0.0,
    ));
    if (mounted) context.push(Routes.reader(bookId));
  }

  /// Sheet hasil ketutup → balik idle, kecuali udah ada import baru jalan.
  VoidCallback _dismissIf(ImportState shown) => () {
    if (identical(ref.read(importControllerProvider), shown)) _import.dismiss();
  };

  /// Banner sesi habis (board Akun 12), di atas kartu Lanjut baca.
  Widget? _sessionBanner() {
    final auth = ref.watch(authControllerProvider).value;
    if (auth == null || !auth.showExpiredBanner) return null;
    return SessionExpiredBanner(
      onSignIn: () => context.go(Routes.login),
      onClose: ref.read(authControllerProvider.notifier).dismissBanner,
    );
  }

  /// Banner pengingat backup (docs/backup.md), atau null.
  Widget? _reminder(List<ShelfBook> books) {
    final last = ref.watch(lastBackupProvider);
    final dismissed = ref.watch(reminderDismissedProvider);
    // Belum kebaca: jangan sempet nongol terus ilang.
    if (!last.hasValue || !dismissed.hasValue || books.isEmpty) return null;
    final days = backupReminderDays(
      now: DateTime.now(),
      lastBackup: last.value?.at,
      firstBook: books
          .map((b) => b.createdAt)
          .reduce((a, b) => a.isBefore(b) ? a : b),
      dismissed: dismissed.value,
    );
    if (days == null) return null;
    return BackupReminder(
      days: days,
      neverBackedUp: last.value == null,
      onBackup: ref.read(backupControllerProvider.notifier).start,
      onClose: () => ref
          .read(settingsRepositoryProvider)
          .dismissReminder(DateTime.now())
          .ignore(),
    );
  }

  File? _cover(String? name) =>
      name == null ? null : ref.read(fileStorageProvider).cover(name);

  /// Menu tekan lama (board 20 Tekan lama buku).
  Future<void> _bookMenu(ShelfBook book) async {
    final pick = await showBookMenu<String>(
      context,
      title: book.title,
      author: book.author,
      coverFile: _cover(book.coverName),
      progress: book.progress,
      opened: book.opened,
      finished: book.finished,
      items: [
        AppMenuItem(
          'info',
          context.l10n.bookshelfBookInfo,
          icon: AppIcons.info,
        ),
        AppMenuItem(
          'delete',
          context.l10n.bookshelfRemoveFromShelf,
          icon: AppIcons.delete,
          destructive: true,
        ),
      ],
    );
    if (!mounted) return;
    switch (pick) {
      case 'info':
        await _openInfo(book);
      case 'delete':
        await _confirmDelete(book);
    }
  }

  Future<void> _openInfo(ShelfBook book) => showAppSheet<void>(
    context,
    builder: (sheet) => BookInfoSheet(
      book: book,
      onRead: () {
        Navigator.of(sheet).pop();
        context.push(Routes.reader(book.id));
      },
      onDelete: () {
        Navigator.of(sheet).pop();
        _confirmDelete(book);
      },
    ),
  );

  Future<void> _confirmDelete(ShelfBook book) async {
    final info = await ref.read(bookInfoProvider(book.id).future);
    if (!mounted) return;
    final lost = [
      if (book.opened)
        context.l10n.bookshelfProgress((book.progress * 100).floor()),
      if (info != null && info.translated > 0)
        context.l10n.bookshelfTranslatedParagraphs(info.translated),
    ].join(context.l10n.bookshelfAnd);
    final ok = await showConfirmDialog(
      context,
      icon: AppIcons.delete,
      title: context.l10n.bookshelfRemoveFromYourShelf(book.title),
      message: context.l10n.bookshelfYourOriginalFileStaysSafe(
        lost.isEmpty ? '' : context.l10n.deletedProgress(lost),
      ),
      cancelLabel: context.l10n.bookshelfNeverMind,
      confirmLabel: context.l10n.bookClear,
    );
    if (!ok || !mounted) return;
    try {
      await ref
          .read(bookRepositoryProvider)
          .delete(book.id, ref.read(fileStorageProvider));
    } on Object {
      if (mounted) {
        showToast(context, context.l10n.bookshelfCouldnTDeleteTheBook);
      }
    }
  }

  Future<void> _pickSort(BuildContext anchor, ShelfSort current) async {
    final pick = await showAppMenu<ShelfSort>(anchor, [
      for (final s in ShelfSort.values)
        AppMenuItem(s, s.label(context.l10n), selected: s == current),
    ], title: context.l10n.bookshelfSortBy);
    if (pick != null && pick != current) {
      ref.read(settingsRepositoryProvider).saveShelfSort(pick).ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(importControllerProvider, _onImport);
    final books = ref.watch(booksStreamProvider);
    final sort = ref.watch(shelfSortProvider).value;
    final view = ref.watch(shelfViewProvider).value;
    // select: persen naik terus, rak gak perlu rebuild tiap kali.
    final importing = ref.watch(
      importControllerProvider.select(
        (s) => s is ImportProcessing ? s.fileName : null,
      ),
    );
    void onImport() => _import.pick();
    final header = ShelfHeader(onImport: onImport);
    // Rak kosong + unduhan jalan = layar 17 (tips sambil nunggu).
    final downloading = ref
        .watch(downloadQueueProvider)
        .where((i) => !i.finished)
        .firstOrNull;
    final baseline = importing == null ? null : _importBaseline;
    final backupReminder = _reminder(switch (books) {
      AsyncData(value: final list) => list,
      _ => const <ShelfBook>[],
    });
    final sessionBanner = _sessionBanner();
    final reminder = sessionBanner == null || backupReminder == null
        ? sessionBanner ?? backupReminder
        : Column(spacing: Space.s3, children: [sessionBanner, backupReminder]);
    return BackupListener(
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: switch (books) {
            // Urutan & tampilan belum kebaca: tahan dulu, biar rak gak sempet
            // nongol dalam urutan/tampilan default terus loncat.
            AsyncData() when sort == null || view == null => _pad(header),
            AsyncData(value: final list)
                when list.isEmpty && importing == null && downloading != null =>
              _EmptyDownloading(header: header, item: downloading),
            AsyncData(value: final list)
                when list.isEmpty && importing == null =>
              _Empty(header: header, onImport: onImport),
            AsyncData(value: final list) => _Shelf(
              books: baseline == null
                  ? list
                  : [
                      for (final b in list)
                        if (b.id <= baseline) b,
                    ],
              sort: sort!,
              view: view!,
              onImport: onImport,
              onSort: _pickSort,
              onView: (v) => ref
                  .read(settingsRepositoryProvider)
                  .saveShelfView(v)
                  .ignore(),
              onBookMenu: _bookMenu,
              importing: importing,
              reminder: reminder,
            ),
            AsyncError() => Column(
              children: [
                _pad(header),
                Expanded(
                  child: Center(
                    child: Text(
                      context.l10n.bookshelfCouldnTOpenYourShelf,
                      style: StabiloType.body.copyWith(
                        color: context.stabilo.ink2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            _ => _pad(header),
          },
        ),
      ),
    );
  }
}

Widget _pad(Widget child) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: Layout.margin),
  child: child,
);

class _Shelf extends ConsumerStatefulWidget {
  const _Shelf({
    required this.books,
    required this.sort,
    required this.view,
    required this.onImport,
    required this.onSort,
    required this.onView,
    required this.onBookMenu,
    this.importing,
    this.reminder,
  });

  /// Urut terakhir dibuka (urutan stream); [sort] diterapin buat isi rak.
  final List<ShelfBook> books;
  final ShelfSort sort;
  final ShelfView view;
  final VoidCallback onImport;
  final void Function(BuildContext anchor, ShelfSort current) onSort;
  final ValueChanged<ShelfView> onView;
  final ValueChanged<ShelfBook> onBookMenu;

  /// Nama file yang lagi diimport: kartu "Lagi diproses" di depan.
  final String? importing;

  /// Pengingat backup, paling atas di area scroll.
  final Widget? reminder;

  @override
  ConsumerState<_Shelf> createState() => _ShelfState();
}

class _ShelfState extends ConsumerState<_Shelf> {
  final _scroll = ScrollController();

  /// Header nyusut ngikutin scroll: 0 (gede) sampe 1 (bar kecil).
  final _collapse = ValueNotifier<double>(0);

  /// Baris "Semua buku" lagi nempel di atas isi yang lewat di bawahnya: fade
  /// tepi atas baru dipasang di bawah baris itu.
  final _stuck = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(
      () =>
          _collapse.value = (_scroll.offset / Layout.barShrink).clamp(0.0, 1.0),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    _collapse.dispose();
    _stuck.dispose();
    super.dispose();
  }

  /// Buku terakhir dibuka yang belum kelar, buat kartu "Lanjut baca yuk".
  ShelfBook? get _resume {
    final first = widget.books.firstOrNull;
    return first != null && first.opened && !first.finished ? first : null;
  }

  void _setStuck(bool v) => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _stuck.value != v) _stuck.value = v;
  });

  File? _cover(ShelfBook b) => b.coverName == null
      ? null
      : ref.read(fileStorageProvider).cover(b.coverName!);

  @override
  Widget build(BuildContext context) {
    // Tab Rak ditap lagi = gulung ke atas (board NavBar).
    ref.listen(tabReselectProvider, (_, _) {
      if (ref.read(tabReselectProvider.notifier).last != LumaTab.rak) return;
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        0,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : Motion.sheetOpen,
        curve: Motion.sheetOpenCurve,
      );
    });
    final c = context.stabilo;
    final sorted = sortShelf(widget.books, widget.sort);
    final resume = _resume;
    final importing = widget.importing;
    final extra = importing == null ? 0 : 1;
    final bottom = MediaQuery.paddingOf(context).bottom;

    final toolbar = _Toolbar(
      sort: widget.sort,
      view: widget.view,
      onSort: widget.onSort,
      onView: widget.onView,
    );

    return Column(
      children: [
        // Header nempel & nyusut pas scroll 0–52pt; lewat itu "Semua buku"
        // nempel di bawah bar.
        _pad(
          ValueListenableBuilder(
            valueListenable: _collapse,
            builder: (context, t, _) =>
                ShelfHeader(collapse: t, onImport: widget.onImport),
          ),
        ),
        Expanded(
          child: ValueListenableBuilder(
            valueListenable: _stuck,
            builder: (context, stuck, child) => EdgeFadeScroll(
              // Mudar cuma di bawah baris yang nempel (44), gak pake garis
              // pemisah. Bawah edge-to-edge: buku jalan sampe tepi layar.
              top: stuck
                  ? const EdgeFadeSide(20, clear: Layout.touch, clearAlpha: 1)
                  : EdgeFadeSide.none,
              bottom: EdgeFadeSide.none,
              child: child!,
            ),
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                if (widget.reminder != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      Layout.margin,
                      Space.s2,
                      Layout.margin,
                      Space.s2,
                    ),
                    sliver: SliverToBoxAdapter(child: widget.reminder),
                  ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    Layout.margin,
                    resume == null ? Space.s4 + Space.s1 : Space.s4,
                    Layout.margin,
                    resume == null ? 0 : Space.s2,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: resume == null
                        ? null
                        : ContinueCard(
                            book: resume,
                            coverFile: _cover(resume),
                            onTap: () => context.push(Routes.reader(resume.id)),
                          ),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _PinnedRow(
                    color: c.canvas,
                    onStuck: _setStuck,
                    child: toolbar,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    Layout.margin,
                    Space.s2,
                    Layout.margin,
                    0,
                  ),
                  sliver: widget.view == ShelfView.list
                      ? SliverFixedExtentList.builder(
                          itemExtent: Layout.rowHeight + Layout.rowGap,
                          itemCount: sorted.length + extra,
                          itemBuilder: (context, i) {
                            if (importing != null) {
                              if (i == 0) {
                                return BookRow.importing(fileName: importing);
                              }
                              i--;
                            }
                            final book = sorted[i];
                            return Padding(
                              key: ValueKey(book.id),
                              padding: const EdgeInsets.only(
                                bottom: Layout.rowGap,
                              ),
                              child: BookRow(
                                title: book.title,
                                author: book.author,
                                coverFile: _cover(book),
                                progress: book.progress,
                                opened: book.opened,
                                finished: book.finished,
                                markdown: book.markdown,
                                onTap: () =>
                                    context.push(Routes.reader(book.id)),
                                onLongPress: () => widget.onBookMenu(book),
                              ),
                            );
                          },
                        )
                      : SliverLayoutBuilder(
                          builder: (context, constraints) {
                            final cols = Layout.shelfColumns(
                              constraints.crossAxisExtent,
                            );
                            final colW = math.max(
                              0.0,
                              (constraints.crossAxisExtent -
                                      (cols - 1) * Layout.shelfGapX) /
                                  cols,
                            );
                            return SliverGrid.builder(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: cols,
                                    crossAxisSpacing: Layout.shelfGapX,
                                    mainAxisSpacing: Layout.shelfGapY,
                                    mainAxisExtent: BookCard.heightFor(colW),
                                  ),
                              itemCount: sorted.length + extra,
                              itemBuilder: (context, i) {
                                if (importing != null) {
                                  if (i == 0) {
                                    return BookCard.importing(
                                      fileName: importing,
                                    );
                                  }
                                  i--;
                                }
                                final book = sorted[i];
                                return BookCard(
                                  key: ValueKey(book.id),
                                  title: book.title,
                                  author: book.author,
                                  coverFile: _cover(book),
                                  progress: book.progress,
                                  opened: book.opened,
                                  finished: book.finished,
                                  markdown: book.markdown,
                                  onTap: () =>
                                      context.push(Routes.reader(book.id)),
                                  onLongPress: () => widget.onBookMenu(book),
                                );
                              },
                            );
                          },
                        ),
                ),
                // Penutup rak.
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    Layout.margin,
                    Space.s6 + Space.s1,
                    Layout.margin,
                    Space.s6 + bottom,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      context.l10n.bookshelfThatSEverythingBooksOnYour(
                        widget.books.length,
                      ),
                      textAlign: TextAlign.center,
                      style: StabiloType.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: c.ink3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Baris "Semua buku" yang nempel di bawah header.
class _PinnedRow extends SliverPersistentHeaderDelegate {
  const _PinnedRow({
    required this.color,
    required this.onStuck,
    required this.child,
  });

  final Color color;
  final ValueChanged<bool> onStuck;
  final Widget child;

  @override
  double get minExtent => Layout.touch;

  @override
  double get maxExtent => Layout.touch;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    onStuck(overlapsContent);
    return ColoredBox(color: color, child: child);
  }

  @override
  bool shouldRebuild(_PinnedRow old) => true;
}

/// "Semua buku" + urutan + toggle grid / list.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.sort,
    required this.view,
    required this.onSort,
    required this.onView,
  });

  final ShelfSort sort;
  final ShelfView view;
  final void Function(BuildContext anchor, ShelfSort current) onSort;
  final ValueChanged<ShelfView> onView;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Layout.margin),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                context.l10n.bookshelfAllBooks,
                // Baris 44 dikunci: ikut teks gede sampe 1,3×.
                textScaler: MediaQuery.textScalerOf(context)
                    .clamp(maxScaleFactor: 1.3),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: StabiloType.titleSm,
              ),
            ),
          ),
          Builder(
            builder: (anchor) => Semantics(
              button: true,
              label: context.l10n.bookshelfShelfOrder(sort.label(context.l10n)),
              excludeSemantics: true,
              child: InkWell(
                onTap: () => onSort(anchor, sort),
                child: SizedBox(
                  height: Layout.touch,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      spacing: 5,
                      children: [
                        Text(
                          sort.label(context.l10n),
                          textScaler: TextScaler.noScaling,
                          style: StabiloType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: c.ink2,
                          ),
                        ),
                        AppIcon(AppIcons.down, size: 13, color: c.ink2),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: Space.s1),
          _ViewToggle(value: view, onChanged: onView),
        ],
      ),
    );
  }
}

/// Toggle 2 ikon (grid / list): 40 tinggi, area tap tiap ikon 44.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.value, required this.onChanged});

  final ShelfView value;
  final ValueChanged<ShelfView> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    Widget item(ShelfView v, List<List<dynamic>> icon, String label) {
      final on = v == value;
      return Semantics(
        button: true,
        selected: on,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(v),
          child: SizedBox(
            width: 34,
            height: Layout.touch,
            child: Center(
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? c.sheet : null,
                  border: on
                      ? Border.all(color: c.capsuleLine, width: Layout.outline)
                      : null,
                ),
                child: AppIcon(icon, size: 16, color: on ? c.ink : c.ink2),
              ),
            ),
          ),
        ),
      );
    }

    // Pil 40 digambar di belakang; ikonnya 44 tinggi biar area tap-nya 44.
    return SizedBox(
      width: 76,
      height: Layout.touch,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: c.muted,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              item(
                ShelfView.grid,
                AppIcons.grid,
                context.l10n.bookshelfGridView,
              ),
              item(
                ShelfView.list,
                AppIcons.list,
                context.l10n.bookshelfListView,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Rak kosong (board Cari buku 02): kalimat pembuka terkenal + Ambil,
/// "Rak lo masih kosong", Cari buku gratis, link import file.
class _Empty extends ConsumerWidget {
  const _Empty({required this.header, required this.onImport});

  final Widget header;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.stabilo;
    final curated = curatedBooks.first;
    final book = curated.book;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Layout.margin,
        0,
        Layout.margin,
        Space.s4 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Space.s6,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 14,
                      children: [
                        Text(
                          context.l10n.bookshelfAFamousOpeningLine,
                          style: StabiloType.caption.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.05 * 13,
                            color: c.ink2,
                          ),
                        ),
                        Text(
                          '“${curated.quote}”',
                          style: StabiloType.reading.copyWith(
                            fontSize: 24,
                            height: 1.45,
                            color: c.ink,
                          ),
                        ),
                        Row(
                          spacing: Space.s3,
                          children: [
                            CatalogCover(book: book, width: 40),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                spacing: 1,
                                children: [
                                  Text(
                                    book.title,
                                    style: StabiloType.label.copyWith(
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  if (book.authorsLabel case final a?)
                                    Text(
                                      a,
                                      style: StabiloType.caption.copyWith(
                                        fontSize: 12.5,
                                        color: c.ink2,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Semantics(
                              button: true,
                              label: context.l10n.bookshelfGet(book.title),
                              excludeSemantics: true,
                              child: GestureDetector(
                                onTap: () => ref
                                    .read(downloadQueueProvider.notifier)
                                    .enqueue(book),
                                child: Container(
                                  height: 40,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.muted,
                                    borderRadius: BorderRadius.circular(
                                      Radii.full,
                                    ),
                                  ),
                                  child: Center(
                                    widthFactor: 1,
                                    child: Text(
                                      context.l10n.bookshelfGet2,
                                      style: StabiloType.label.copyWith(
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.only(top: 22),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: c.track,
                            width: Layout.outline,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 6,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: context.l10n.bookshelfYourShelfIsStill,
                                ),
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.baseline,
                                  baseline: TextBaseline.alphabetic,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: c.accent,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      context.l10n.bookshelfEmpty,
                                      style: StabiloType.display.copyWith(
                                        color: c.onAccent,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            style: StabiloType.display.copyWith(color: c.ink),
                          ),
                          Text(
                            context.l10n.bookshelfGetTheBookAboveOrFind,
                            style: StabiloType.body.copyWith(color: c.ink2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.s4),
          AppButton.primary(
            label: context.l10n.bookshelfFindFreeBooks,
            icon: HugeIcons.strokeRoundedSearch01,
            height: 56,
            onPressed: () => context.go(Routes.discover),
          ),
          const SizedBox(height: 10),
          Semantics(
            button: true,
            child: GestureDetector(
              onTap: onImport,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 6,
                children: [
                  AppIcon(
                    HugeIcons.strokeRoundedFile01,
                    size: 16,
                    color: c.ink2,
                  ),
                  Flexible(
                    child: Text(
                      textAlign: TextAlign.center,
                      context.l10n.bookshelfOrImportEpubMarkdownFromFiles,
                      style: StabiloType.caption.copyWith(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: c.ink2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rak kosong, buku pertama lagi diunduh (board Cari buku 17): progres tipis
/// + kartu tips geser, kartu pertama pakai kalimat pembuka buku yang diunduh.
class _EmptyDownloading extends StatefulWidget {
  const _EmptyDownloading({required this.header, required this.item});

  final Widget header;
  final DownloadItem item;

  @override
  State<_EmptyDownloading> createState() => _EmptyDownloadingState();
}

class _EmptyDownloadingState extends State<_EmptyDownloading> {
  var _page = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final item = widget.item;
    final curated = curatedFor(item.book);
    final progress = item.progress.clamp(0.0, 1.0);
    final tips = [
      (
        context.l10n.bookshelfTapAParagraphWhenYouGet,
        _Example(quote: curated.quote, meaning: curated.meaning),
      ),
      (
        context.l10n.bookshelfPuzzledByASentenceBreakIt,
        _Tip(context.l10n.bookshelfFromTheTranslationSheetTapBreakdown),
      ),
      (
        context.l10n.bookshelfChatAboutTheBookAnytime,
        _Tip(context.l10n.bookshelfAskAboutCharactersThePlotOr),
      ),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Layout.margin,
        0,
        Layout.margin,
        MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.s4,
        children: [
          widget.header,
          Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: c.muted,
                borderRadius: BorderRadius.circular(Radii.menu),
              ),
              child: Row(
                spacing: Space.s3,
                children: [
                  CatalogCover(book: item.book, width: 30),
                  Expanded(
                    child: Column(
                      spacing: 6,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                context.l10n.bookshelfDownloading(
                                  item.book.title,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: StabiloType.label.copyWith(
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                            Text(
                              '${(progress * 100).round()}%',
                              style: StabiloType.label.copyWith(fontSize: 13.5),
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
                ],
              ),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 22,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 6,
                  children: [
                    Text(
                      context.l10n.bookshelfWhileYouWaitOf(
                        _page + 1,
                        tips.length,
                      ),
                      style: StabiloType.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.05 * 13,
                        color: c.ink2,
                      ),
                    ),
                    Text(
                      tips[_page].$1,
                      style: StabiloType.display.copyWith(color: c.ink),
                    ),
                  ],
                ),
                SizedBox(
                  height: 220,
                  child: PageView(
                    onPageChanged: (i) => setState(() => _page = i),
                    children: [
                      for (final (_, card) in tips)
                        Center(child: SingleChildScrollView(child: card)),
                    ],
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 6,
                  children: [
                    for (var i = 0; i < tips.length; i++)
                      AnimatedContainer(
                        duration: Motion.highlight,
                        width: i == _page ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == _page ? c.ink : c.track,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: c.sheet,
          border: Border.all(color: c.outline, width: Layout.outline),
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: Text(
          text,
          style: StabiloType.reading.copyWith(
            fontSize: 16,
            height: 1.6,
            color: c.ink,
          ),
        ),
      ),
    );
  }
}

/// Contoh fitur di rak kosong: paragraf distabilo + gelembung artinya.
class _Example extends StatelessWidget {
  const _Example({
    this.quote =
        'It is a truth universally acknowledged, that a single man in '
        'possession of a good fortune, must be in want of a wife.',
    this.meaning =
        'Udah jadi rahasia umum: cowok tajir pasti lagi nyari istri.',
  });

  final String quote, meaning;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final light = Theme.of(context).brightness == Brightness.light;
    const deg = math.pi / 180;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Transform.rotate(
            angle: -1.5 * deg,
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
              decoration: BoxDecoration(
                color: c.sheet,
                border: Border.all(color: c.outline, width: Layout.outline),
                borderRadius: BorderRadius.circular(Radii.lg),
                boxShadow: light ? Elevation.cover : null,
              ),
              child: Text(
                quote,
                style: StabiloType.reading.copyWith(
                  fontSize: 16,
                  height: 1.6,
                  color: c.onHighlight,
                  backgroundColor: c.highlight,
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -12),
            child: Padding(
              padding: const EdgeInsets.only(left: 64),
              child: Transform.rotate(
                angle: 1.2 * deg,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.s4,
                    vertical: Space.s3,
                  ),
                  decoration: BoxDecoration(
                    color: c.pink,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(Radii.lg),
                      topRight: Radius.circular(Radii.lg),
                      bottomRight: Radius.circular(Radii.lg),
                      bottomLeft: Radius.circular(6),
                    ),
                    boxShadow: light ? Elevation.cover : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Space.s1,
                    children: [
                      Text(
                        context.l10n.bookshelfHereSWhatItMeans,
                        style: StabiloType.tag.copyWith(color: c.onPink),
                      ),
                      Text(
                        meaning,
                        style: StabiloType.label.copyWith(
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                          color: c.onPink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
