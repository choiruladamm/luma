import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../data/services/file_storage.dart';
import '../../../../domain/models/book.dart';
import '../../../../routing/router.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/book_card.dart';
import '../../../core/widgets/edge_fade.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/book_cover.dart';
import '../../../core/widgets/luma_logo.dart';
import '../../../core/widgets/sheet.dart';
import '../../../core/widgets/toast.dart';
import '../../import_book/view_models/import_view_model.dart';
import '../../import_book/views/import_sheets.dart';
import '../view_models/bookshelf_view_model.dart';

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

  File? _cover(String? name) =>
      name == null ? null : ref.read(fileStorageProvider).cover(name);

  @override
  Widget build(BuildContext context) {
    ref.listen(importControllerProvider, _onImport);
    final books = ref.watch(booksStreamProvider);
    final importing = switch (ref.watch(importControllerProvider)) {
      ImportProcessing(:final fileName) => fileName,
      _ => null,
    };
    void onImport() => _import.pick();
    final header = _Header(onImport: onImport);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: switch (books) {
          AsyncData(value: final list) when list.isEmpty && importing == null =>
            _Empty(header: header, onImport: onImport),
          AsyncData(value: final list) => _Shelf(
            header: header,
            books: list,
            importing: importing,
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
    );
  }
}

Widget _pad(Widget child) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: Layout.margin),
  child: child,
);

class _Header extends StatelessWidget {
  const _Header({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: Layout.topBar,
      child: Row(
        children: [
          Transform.translate(
            offset: const Offset(-3, 0),
            child: const LumaLogo(),
          ),
          const SizedBox(width: Space.s2 - 3),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                'Rak buku lo',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: StabiloType.titleLg,
              ),
            ),
          ),
          CircleButton(
            semanticLabel: 'Import EPUB',
            icon: AppIcons.add,
            primary: true,
            onPressed: onImport,
          ),
          const SizedBox(width: Space.s2),
          CircleButton(
            semanticLabel: 'Pengaturan app',
            icon: AppIcons.settings,
            onPressed: () => context.push(Routes.settings),
          ),
        ],
      ),
    );
  }
}

class _Shelf extends ConsumerWidget {
  const _Shelf({required this.header, required this.books, this.importing});

  final Widget header;
  final List<ShelfBook> books;

  /// Nama file yang lagi diimport: kartu "Lagi diproses" di depan.
  final String? importing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Header + "Semua buku" nempel; grid di bawahnya mudar pas lewat (board
    // EdgeFade), gak pake garis pemisah.
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Layout.margin),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: Space.s4 + Space.s1),
              SizedBox(
                height: Layout.touch,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    header: true,
                    child: Text('Semua buku', style: StabiloType.titleSm),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: EdgeFadeScroll(
            // Bawah edge-to-edge: buku jalan sampe tepi layar, lewat di
            // bawah home indicator; padding akhir = safe area.
            bottom: EdgeFadeSide.none,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    Layout.margin,
                    Space.s2,
                    Layout.margin,
                    MediaQuery.paddingOf(context).bottom,
                  ),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      const cols = Layout.shelfColumns;
                      final colW = math.max(
                        0.0,
                        (constraints.crossAxisExtent -
                                (cols - 1) * Layout.shelfGapX) /
                            cols,
                      );
                      return SliverGrid.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          crossAxisSpacing: Layout.shelfGapX,
                          mainAxisSpacing: Layout.shelfGapY,
                          mainAxisExtent: BookCard.heightFor(colW),
                        ),
                        itemCount: books.length + (importing == null ? 0 : 1),
                        itemBuilder: (context, i) {
                          if (importing != null) {
                            if (i == 0) {
                              return BookCard.importing(fileName: importing!);
                            }
                            i--;
                          }
                          final book = books[i];
                          return BookCard(
                            key: ValueKey(book.id),
                            title: book.title,
                            author: book.author,
                            coverFile: book.coverName == null
                                ? null
                                : ref
                                      .read(fileStorageProvider)
                                      .cover(book.coverName!),
                            // Progres & "Kelar!" nyusul di #15.
                            progress: 0,
                            opened: book.opened,
                            finished: false,
                            onTap: () => context.push(Routes.reader(book.id)),
                          );
                        },
                      );
                    },
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
