import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../data/repositories/book_repository.dart';
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
import '../../../core/widgets/dialog.dart';
import '../../../core/widgets/menu.dart';
import '../../../core/widgets/sheet.dart';
import '../../../core/widgets/toast.dart';
import '../../import_book/view_models/import_view_model.dart';
import '../../import_book/views/import_sheets.dart';
import '../../settings/view_models/backup_view_model.dart';
import '../../settings/views/backup_listener.dart';
import '../view_models/bookshelf_view_model.dart';
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

  ImportController get _import => ref.read(importControllerProvider.notifier);

  void _onImport(ImportState? prev, ImportState next) {
    if (next is! ImportProcessing && _progressOpen) {
      _progressOpen = false;
      Navigator.of(context).pop();
    }
    switch (next) {
      case ImportProcessing() when !_progressOpen:
        _progressOpen = true;
        showAppSheet<void>(
          context,
          dismissible: false,
          builder: (_) => const ImportProgressSheet(),
        );
      case ImportSuccess(:final book):
        _import.dismiss();
        showToast(
          context,
          'Sip, udah masuk rak!',
          subtitle: [book.title, ?book.author].join(' · '),
          leading: BookCover(
            title: book.title,
            width: 30,
            file: _cover(book.coverName),
          ),
          actionLabel: 'Baca',
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
      default:
    }
  }

  /// Sheet hasil ketutup → balik idle, kecuali udah ada import baru jalan.
  VoidCallback _dismissIf(ImportState shown) => () {
    if (identical(ref.read(importControllerProvider), shown)) _import.dismiss();
  };

  /// Banner pengingat backup (docs bagian 10), atau null.
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

  /// Menu tekan lama, nempel ke kartu ([anchor]).
  Future<void> _bookMenu(BuildContext anchor, ShelfBook book) async {
    final pick = await showAppMenu<String>(anchor, const [
      AppMenuItem('info', 'Info buku', icon: AppIcons.info),
      AppMenuItem(
        'delete',
        'Hapus dari rak',
        icon: AppIcons.delete,
        destructive: true,
      ),
    ]);
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
      coverFile: _cover(book.coverName),
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
      if (book.opened) 'Progres ${(book.progress * 100).floor()}%',
      if (info != null && info.translated > 0)
        '${info.translated} paragraf yang udah diartiin',
    ].join(' sama ');
    final ok = await showConfirmDialog(
      context,
      icon: AppIcons.delete,
      title: 'Hapus "${book.title}" dari rak?',
      message:
          '${lost.isEmpty ? '' : '$lost ikut kehapus. '}'
          'File aslinya di Files tetep aman kok.',
      cancelLabel: 'Gak jadi',
      confirmLabel: 'Hapus',
    );
    if (!ok || !mounted) return;
    try {
      await ref
          .read(bookRepositoryProvider)
          .delete(book.id, ref.read(fileStorageProvider));
    } on Object {
      if (mounted) showToast(context, 'Yah, gagal ngehapus bukunya');
    }
  }

  Future<void> _pickSort(BuildContext anchor, ShelfSort current) async {
    final pick = await showAppMenu<ShelfSort>(anchor, [
      for (final s in ShelfSort.values)
        AppMenuItem(s, s.label, selected: s == current),
    ], title: 'Urutin pake');
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
    final importing = switch (ref.watch(importControllerProvider)) {
      ImportProcessing(:final fileName) => fileName,
      _ => null,
    };
    void onImport() => _import.pick();
    final header = ShelfHeader(onImport: onImport);
    final reminder = _reminder(switch (books) {
      AsyncData(value: final list) => list,
      _ => const <ShelfBook>[],
    });
    return BackupListener(
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: switch (books) {
            // Urutan & tampilan belum kebaca: tahan dulu, biar rak gak sempet
            // nongol dalam urutan/tampilan default terus loncat.
            AsyncData() when sort == null || view == null => _pad(header),
            AsyncData(value: final list)
                when list.isEmpty && importing == null =>
              _Empty(header: header, onImport: onImport),
            AsyncData(value: final list) => _Shelf(
              books: list,
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
                      'Yah, rak-nya gagal kebuka',
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
  final void Function(BuildContext anchor, ShelfBook book) onBookMenu;

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
                              child: Builder(
                                builder: (anchor) => BookRow(
                                  title: book.title,
                                  author: book.author,
                                  coverFile: _cover(book),
                                  progress: book.progress,
                                  opened: book.opened,
                                  finished: book.finished,
                                  onTap: () =>
                                      context.push(Routes.reader(book.id)),
                                  onLongPress: () =>
                                      widget.onBookMenu(anchor, book),
                                ),
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
                                return Builder(
                                  key: ValueKey(book.id),
                                  builder: (anchor) => BookCard(
                                    title: book.title,
                                    author: book.author,
                                    coverFile: _cover(book),
                                    progress: book.progress,
                                    opened: book.opened,
                                    finished: book.finished,
                                    onTap: () =>
                                        context.push(Routes.reader(book.id)),
                                    onLongPress: () =>
                                        widget.onBookMenu(anchor, book),
                                  ),
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
                      'Udah mentok. ${widget.books.length} buku di rak lo.',
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
                'Semua buku',
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
              label: 'Urutan rak: ${sort.label}',
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
                          sort.label,
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
              item(ShelfView.grid, AppIcons.grid, 'Tampilan grid'),
              item(ShelfView.list, AppIcons.list, 'Tampilan list'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.header, required this.onImport});

  final Widget header;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
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
                  spacing: Space.s8,
                  children: [
                    const _Example(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: Space.s2,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(text: 'Belum ada '),
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
                                    'buku',
                                    style: StabiloType.display.copyWith(
                                      color: c.onAccent,
                                    ),
                                  ),
                                ),
                              ),
                              const TextSpan(text: ' nih'),
                            ],
                          ),
                          style: StabiloType.display.copyWith(color: c.ink),
                        ),
                        Text(
                          'Import EPUB dulu gih. Abis itu tap paragraf mana aja '
                          'yang bikin pusing, artinya langsung nongol kayak di '
                          'atas.',
                          style: StabiloType.body.copyWith(color: c.ink2),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.s4),
          AppButton.primary(
            label: 'Import EPUB',
            icon: AppIcons.add,
            height: 56,
            onPressed: onImport,
          ),
          const SizedBox(height: Space.s3),
          Text(
            'Ambil dari app Files, format .epub aja',
            textAlign: TextAlign.center,
            style: StabiloType.caption.copyWith(color: c.ink2),
          ),
        ],
      ),
    );
  }
}

/// Contoh fitur di rak kosong: paragraf distabilo + gelembung artinya.
class _Example extends StatelessWidget {
  const _Example();

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
                'It is a truth universally acknowledged, that a single man in '
                'possession of a good fortune, must be in want of a wife.',
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
                        'ARTINYA GINI NIH',
                        style: StabiloType.tag.copyWith(color: c.onPink),
                      ),
                      Text(
                        'Udah jadi rahasia umum: cowok tajir pasti lagi nyari '
                        'istri.',
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
