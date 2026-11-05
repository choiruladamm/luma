import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../../data/repositories/catalog_repository.dart';
import '../../../../data/services/catalog_sync_service.dart';
import '../../../../domain/models/catalog.dart';
import '../../../../routing/router.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/tag.dart';
import '../view_models/discover_view_model.dart';
import '../view_models/download_queue_view_model.dart';
import 'catalog_cover.dart';
import 'discover_states.dart';

/// Tab Cari buku (board 09 · Cari buku, layar 03–09). Katalog lokal belum ada
/// = nyiapin dulu (layout layar 07); kolom kosong = Top chart; ketik = hasil.
class DiscoverView extends ConsumerStatefulWidget {
  const DiscoverView({super.key});

  @override
  ConsumerState<DiscoverView> createState() => _DiscoverViewState();
}

class _DiscoverViewState extends ConsumerState<DiscoverView> {
  final _field = TextEditingController();
  final _scroll = ScrollController();
  var _setupStarted = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 200) {
        ref.read(discoverProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _field.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _setQuery(String q) {
    if (_field.text != q) _field.text = q;
    ref.read(discoverProvider.notifier).setQuery(q);
  }

  @override
  Widget build(BuildContext context) {
    // Query bisa diisi dari luar (tap penulis di detail buku): kolomnya ikut.
    ref.listen(discoverProvider.select((s) => s.query), (_, q) {
      if (_field.text != q) _field.text = q;
    });
    final state = ref.watch(discoverProvider);
    final stats = ref.watch(catalogStatsProvider).value;
    final sync = ref.watch(catalogSyncProvider);
    final ready = stats != null && stats.count > 0;
    if (stats != null && !ready && !_setupStarted) {
      _setupStarted = true;
      Future(() => ref.read(catalogSyncProvider.notifier).sync());
    }
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Layout.margin),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.s4,
            children: [
              SizedBox(
                height: Layout.topBar,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    header: true,
                    child: Text('Cari buku', style: StabiloType.titleLg),
                  ),
                ),
              ),
              _SearchField(
                controller: _field,
                enabled: ready,
                onChanged: _setQuery,
              ),
              Expanded(
                child: switch ((ready, state.results)) {
                  (false, _) => _CatalogSetup(
                    state: sync,
                    bottom: bottom,
                    onRetry: () => ref
                        .read(catalogSyncProvider.notifier)
                        .sync(force: true),
                  ),
                  (true, null) => _TopChart(
                    popular: state.popular,
                    bottom: bottom,
                    onRetry: ref.read(discoverProvider.notifier).loadPopular,
                    onPreset: _setQuery,
                  ),
                  (true, final results?) => _Results(
                    results: results,
                    scroll: _scroll,
                    bottom: bottom,
                    onRetryMore: ref.read(discoverProvider.notifier).loadMore,
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kolom cari 56, kapsul outline (board 03). Tombol × 26 pas ada isi.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final b = Theme.of(context).brightness;
    return Container(
      height: 56,
      padding: const EdgeInsets.only(left: 18, right: 14),
      decoration: BoxDecoration(
        color: c.sheet,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: c.outline, width: Layout.outline),
        boxShadow: Elevation.press(c, b),
      ),
      child: Row(
        spacing: 10,
        children: [
          AppIcon(HugeIcons.strokeRoundedSearch01, color: c.ink2),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: StabiloType.body.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
              decoration: InputDecoration(
                hintText: 'Judul atau nama penulis',
                hintStyle: StabiloType.body.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: c.ink2,
                ),
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (_, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : Semantics(
                    button: true,
                    label: 'Hapus kata cari',
                    child: GestureDetector(
                      onTap: () => onChanged(''),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: c.muted,
                          shape: BoxShape.circle,
                        ),
                        child: AppIcon(AppIcons.close, size: 14, color: c.ink),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Katalog lokal belum ada: layout layar 07 dengan copy "Nyiapin katalog
/// buku…", gagal = layar 08 (docs/discover.md, Board).
class _CatalogSetup extends StatelessWidget {
  const _CatalogSetup({
    required this.state,
    required this.bottom,
    required this.onRetry,
  });

  final CatalogSyncState state;
  final double bottom;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = state is CatalogSyncFailed;
    final text = switch (state) {
      CatalogSyncDownloading(:final progress) when progress >= 0 =>
        'Nyiapin katalog buku… ${(progress * 100).round()}%',
      CatalogSyncImporting() => 'Nyusun katalog…',
      _ => 'Nyiapin katalog buku…',
    };
    return ListView(
      padding: EdgeInsets.only(bottom: bottom),
      children: [
        if (failed)
          DiscoverNotice(
            icon: AppIcons.alert,
            title: 'Katalog lagi gak bisa dihubungin',
            body: 'Bukan salah lo kok. Coba lagi bentar lagi ya.',
            onRetry: onRetry,
          )
        else
          DiscoverNotice(
            icon: AppIcons.loading,
            spinning: true,
            title: text,
            body: 'Sekali aja, abis itu nyari jalan tanpa internet.',
          ),
        if (!failed) const SkeletonRows(),
      ],
    );
  }
}

/// Layar 03 (+ 07 / 08 / 09 buat jalur jaringan).
class _TopChart extends ConsumerWidget {
  const _TopChart({
    required this.popular,
    required this.bottom,
    required this.onRetry,
    required this.onPreset,
  });

  final PopularState popular;
  final double bottom;
  final VoidCallback onRetry;
  final ValueChanged<String> onPreset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.stabilo;
    final items = switch (popular) {
      PopularReady(:final items) => items,
      _ => const <CatalogBook>[],
    };
    return ListView(
      padding: EdgeInsets.only(bottom: bottom),
      children: [
        if (popular case PopularFailed(failure: NetworkFailure.offline))
          DiscoverEmpty(
            icon: AppIcons.offline,
            title: 'Lo lagi offline',
            body:
                'Nyari tetep jalan. Tapi daftar rame, detail buku, sama '
                'unduhan butuh internet. Buku di rak tetap bisa lo baca kok.',
            action: AppButton.primary(
              label: 'Buka rak',
              pill: true,
              height: 48,
              onPressed: () => context.go(Routes.home),
            ),
          )
        else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'LAGI RAME',
                style: StabiloType.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.05 * 13,
                  color: c.ink2,
                ),
              ),
              Text(
                'Top ${DiscoverViewModel.topCount}',
                style: StabiloType.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: c.ink2,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.s4),
          switch (popular) {
            PopularFailed() => DiscoverNotice(
              icon: AppIcons.alert,
              title: 'Katalog lagi gak bisa dihubungin',
              body: 'Bukan salah lo kok. Coba lagi bentar lagi ya.',
              onRetry: onRetry,
            ),
            PopularLoading(slow: true) => DiscoverNotice(
              icon: AppIcons.history,
              title: 'Katalognya lagi lemot nih',
              body: 'Udah 5 detik lebih. Tungguin bentar, atau coba lagi.',
              onRetry: onRetry,
            ),
            PopularLoading() => const SkeletonRows(),
            PopularReady() => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.s4,
              children: [
                if (items.isNotEmpty) _TopCard(book: items.first),
                if (items.length > 1) _RankRow(books: items.skip(1).toList()),
              ],
            ),
          },
          if (popular case PopularLoading(slow: true)) const SkeletonRows(),
          const SizedBox(height: Space.s5),
          Text(
            'COBA CARI',
            style: StabiloType.caption.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.05 * 13,
              color: c.ink2,
            ),
          ),
          const SizedBox(height: Space.s3),
          Wrap(
            spacing: Space.s2,
            runSpacing: Space.s2,
            children: [
              for (final p in DiscoverViewModel.presets)
                Semantics(
                  button: true,
                  child: GestureDetector(
                    onTap: () => onPreset(p),
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: c.muted,
                        borderRadius: BorderRadius.circular(Radii.full),
                      ),
                      // widthFactor: 1 = selebar teks (alignment bikin melar).
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          p,
                          style: StabiloType.caption.copyWith(
                            fontWeight: FontWeight.w700,
                            color: c.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Kartu kuning "#1 lagi rame" (board 03).
class _TopCard extends StatelessWidget {
  const _TopCard({required this.book});

  final CatalogBook book;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final b = Theme.of(context).brightness;
    return Semantics(
      button: true,
      label: '#1 lagi rame, ${book.title}',
      child: GestureDetector(
        onTap: () => context.push(Routes.catalogBook(book), extra: book),
        child: Container(
          height: 168,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.accent,
            borderRadius: BorderRadius.circular(Radii.dialog),
            border: Border.all(color: c.accentBorder, width: Layout.outline),
            boxShadow: Elevation.press(c, b),
          ),
          child: Stack(
            children: [
              Positioned(
                right: 122,
                bottom: -8,
                child: _RankNumber(1, size: 96),
              ),
              Positioned(
                right: 20,
                top: 18,
                child: CatalogCover(book: book, width: 92),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 130, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 3,
                      children: [
                        Text(
                          '#1 lagi rame',
                          style: StabiloType.micro.copyWith(
                            fontSize: 12.5,
                            color: c.onAccent,
                          ),
                        ),
                        Text(
                          book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: StabiloType.titleMd.copyWith(
                            fontSize: 22,
                            height: 1.05,
                            color: c.onAccent,
                          ),
                        ),
                        if (book.authorsLabel case final a?)
                          Text(
                            a,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: StabiloType.caption.copyWith(
                              fontSize: 13.5,
                              color: c.onAccent,
                            ),
                          ),
                      ],
                    ),
                    _BookStatus(book: book),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Baris geser #2… (board 03): angka outline besar nempel kiri bawah cover.
class _RankRow extends StatelessWidget {
  const _RankRow({required this.books});

  final List<CatalogBook> books;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return SizedBox(
      height: 132 + 6 + 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: books.length,
        separatorBuilder: (_, _) => const SizedBox(width: 18),
        itemBuilder: (_, i) {
          final book = books[i];
          return Semantics(
            button: true,
            label: '#${i + 2}, ${book.title}',
            child: GestureDetector(
              onTap: () => context.push(Routes.catalogBook(book), extra: book),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 6,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 34),
                        child: CatalogCover(book: book, width: 88),
                      ),
                      Positioned(
                        left: 0,
                        bottom: -4,
                        child: _RankNumber(i + 2, size: 78),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 34),
                    child: SizedBox(
                      width: 88,
                      child: Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: StabiloType.caption.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Angka peringkat: isi sheet + garis outline 2 (board 03).
class _RankNumber extends StatelessWidget {
  const _RankNumber(this.n, {required this.size});

  final int n;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final base = TextStyle(
      fontFamily: StabiloType.ui,
      fontSize: size,
      fontWeight: FontWeight.w800,
      height: 0.8,
      letterSpacing: -0.06 * size,
    );
    return ExcludeSemantics(
      child: Stack(
        children: [
          Text(
            '$n',
            style: base.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2
                ..strokeJoin = StrokeJoin.round
                ..color = c.outline,
            ),
          ),
          Text('$n', style: base.copyWith(color: c.sheet)),
        ],
      ),
    );
  }
}

/// Layar 04 / 05 / 06.
class _Results extends ConsumerWidget {
  const _Results({
    required this.results,
    required this.scroll,
    required this.bottom,
    required this.onRetryMore,
  });

  final SearchResults results;
  final ScrollController scroll;
  final double bottom;
  final VoidCallback onRetryMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.stabilo;
    if (results.items.isEmpty) {
      return DiscoverEmpty(
        icon: HugeIcons.strokeRoundedSearchRemove,
        title: 'Gak nemu “${results.query}”',
        body:
            'Pencarian cuma nyocokin judul sama nama penulis. Cek ejaannya, '
            'atau coba kata yang lebih pendek.',
      );
    }
    final rest = results.items.skip(1).toList();
    return ListView(
      controller: scroll,
      padding: EdgeInsets.only(bottom: bottom),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                'HASIL BUAT “${results.query.toUpperCase()}”',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: StabiloType.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.05 * 13,
                  color: c.ink2,
                ),
              ),
            ),
            Text(
              '${results.total} hasil · urut paling cocok',
              style: StabiloType.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: c.ink2,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.s4),
        _BestMatch(book: results.items.first),
        for (final (i, book) in rest.indexed) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: c.track),
          _ResultRow(book: book),
        ],
        if (results.moreFailed)
          _Footer(
            label: 'Gagal ngambil. Coba lagi',
            icon: AppIcons.retry,
            onTap: onRetryMore,
          )
        else if (results.hasMore)
          _Footer(
            label: 'Ngambil ${CatalogRepository.pageSize} lagi…',
            icon: AppIcons.loading,
            spinning: true,
          ),
      ],
    );
  }
}

/// Hasil teratas: kartu putih outline "Paling cocok" (board 05).
class _BestMatch extends StatelessWidget {
  const _BestMatch({required this.book});

  final CatalogBook book;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final b = Theme.of(context).brightness;
    return Semantics(
      button: true,
      label: 'Paling cocok, ${book.title}',
      child: GestureDetector(
        onTap: () => context.push(Routes.catalogBook(book), extra: book),
        child: Container(
          padding: const EdgeInsets.all(Space.s4),
          decoration: BoxDecoration(
            color: c.sheet,
            borderRadius: BorderRadius.circular(Radii.dialog),
            border: Border.all(color: c.outline, width: Layout.outline),
            boxShadow: Elevation.press(c, b),
          ),
          child: Row(
            spacing: Space.s4,
            children: [
              CatalogCover(book: book, width: 84),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 3,
                  children: [
                    Text(
                      'Paling cocok',
                      style: StabiloType.micro.copyWith(
                        fontSize: 12.5,
                        color: c.ink2,
                      ),
                    ),
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: StabiloType.titleMd.copyWith(
                        fontSize: 21,
                        height: 1.08,
                      ),
                    ),
                    if (book.authorsLabel case final a?)
                      Text(
                        a,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: StabiloType.caption.copyWith(
                          fontSize: 13.5,
                          color: c.ink2,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: _BookStatus(book: book),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Baris hasil: cover 60, judul, penulis, status (board 05).
class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.book});

  final CatalogBook book;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      button: true,
      label: book.title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.push(Routes.catalogBook(book), extra: book),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            spacing: 14,
            children: [
              CatalogCover(book: book, width: 60),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 3,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: StabiloType.titleXs.copyWith(height: 1.2),
                    ),
                    if (book.authorsLabel case final a?)
                      Text(
                        a,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: StabiloType.caption.copyWith(
                          fontSize: 13.5,
                          color: c.ink2,
                        ),
                      ),
                    _BookStatus(book: book, topGap: 4),
                  ],
                ),
              ),
              AppIcon(AppIcons.chevron, size: 16, color: c.ink3),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Udah di rak" / "Lagi diunduh · 43%" / "Antri"; kosong kalau gak ada.
class _BookStatus extends ConsumerWidget {
  const _BookStatus({required this.book, this.topGap = 0});

  final CatalogBook book;
  final double topGap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shelf = ref.watch(shelfExternalIdsProvider(book.sourceId)).value;
    final item = ref.watch(
      downloadQueueProvider.select(
        (q) => q
            .where(
              (i) =>
                  i.book.sourceId == book.sourceId &&
                  i.book.externalId == book.externalId &&
                  !i.finished,
            )
            .firstOrNull,
      ),
    );
    final tag = switch ((shelf?.contains(book.externalId) ?? false, item)) {
      (true, _) => Tag.status('Udah di rak', icon: AppIcons.check),
      (_, DownloadItem(status: DownloadStatus.queued)) => const Tag.status(
        'Antri',
      ),
      (_, DownloadItem(:final progress)) => Tag.status(
        'Lagi diunduh · ${(progress.clamp(0.0, 1.0) * 100).round()}%',
        icon: HugeIcons.strokeRoundedDownload04,
      ),
      _ => null,
    };
    if (tag == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: topGap),
      child: Align(alignment: Alignment.centerLeft, child: tag),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.label,
    required this.icon,
    this.onTap,
    this.spinning = false,
  });

  final String label;
  final List<List<dynamic>> icon;
  final VoidCallback? onTap;
  final bool spinning;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 10,
            children: [
              if (spinning)
                SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.ink2,
                  ),
                )
              else
                AppIcon(icon, size: 16, color: c.ink2),
              Text(
                label,
                style: StabiloType.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: c.ink2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
