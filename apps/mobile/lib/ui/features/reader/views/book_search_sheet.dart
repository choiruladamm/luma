import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/book_search.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/edge_fade.dart';
import '../../../core/widgets/search_field.dart';
import '../../../core/widgets/search_result.dart';
import '../../../core/widgets/sheet.dart';
import '../view_models/book_search_view_model.dart';

/// Sheet Cari kata (board "10 · Cari kata", layar 1–5). Detent penuh, mulai
/// [Layout.searchSheetTop] dari atas. Balikin hasil yang di-tap, null kalau
/// ditutup.
Future<BookSearchPick?> showBookSearchSheet(
  BuildContext context, {
  required int bookId,
  int? currentChapterId,

  /// Kata + posisi daftar buat buka lagi dari navigator (mode cari).
  String? initialQuery,
  double initialScrollOffset = 0,
  ValueChanged<double>? onScrollOffset,
}) {
  final height = MediaQuery.sizeOf(context).height;
  return showAppSheet<BookSearchPick>(
    context,
    maxHeight: (height - Layout.searchSheetTop) / height,
    builder: (_) => BookSearchSheet(
      bookId: bookId,
      currentChapterId: currentChapterId,
      initialQuery: initialQuery,
      initialScrollOffset: initialScrollOffset,
      onScrollOffset: onScrollOffset,
    ),
  );
}

class BookSearchSheet extends ConsumerStatefulWidget {
  const BookSearchSheet({
    super.key,
    required this.bookId,
    this.currentChapterId,
    this.initialQuery,
    this.initialScrollOffset = 0,
    this.onScrollOffset,
  });

  final int bookId;

  /// Bab yang lagi dibaca: dikasih chip "Lagi dibaca".
  final int? currentChapterId;

  /// Kolom cari langsung keisi dan dicari (balik dari navigator).
  final String? initialQuery;

  /// Posisi scroll daftar hasil yang diinget.
  final double initialScrollOffset;
  final ValueChanged<double>? onScrollOffset;

  @override
  ConsumerState<BookSearchSheet> createState() => _BookSearchSheetState();
}

class _BookSearchSheetState extends ConsumerState<BookSearchSheet> {
  final _controller = TextEditingController();
  late final _scroll = ScrollController(
    initialScrollOffset: widget.initialScrollOffset,
  );

  @override
  void initState() {
    super.initState();
    final q = widget.initialQuery;
    if (q != null) {
      _controller.text = q;
      // Provider baru dibikin pas build pertama; cari begitu siap.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _vm.searchNow(q);
      });
    }
    _scroll.addListener(() {
      if (_scroll.hasClients) widget.onScrollOffset?.call(_scroll.offset);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  BookSearchViewModel get _vm =>
      ref.read(bookSearchProvider(widget.bookId).notifier);

  Future<void> _pick(BookSearchState s, BookSearchHit hit) async {
    final query = s.query.trim();
    await _vm.remember();
    if (!mounted) return;
    Navigator.of(context)
        .pop<BookSearchPick>((query: query, result: s.result, hit: hit));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final s = ref.watch(bookSearchProvider(widget.bookId));
    final media = MediaQuery.of(context);
    return SizedBox(
      height: media.size.height - Layout.searchSheetTop,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Layout.sheetPadding.left - 4,
          Layout.sheetPadding.top,
          Layout.sheetPadding.right - 4,
          media.viewInsets.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 14,
          children: [
            const SheetGrabber(),
            Row(
              spacing: Space.s3,
              children: [
                Expanded(
                  child: SearchField(
                    controller: _controller,
                    hint: 'Cari kata di buku ini',
                    autofocus: true,
                    onChanged: _vm.setQuery,
                    onSubmitted: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                  ),
                ),
                Semantics(
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: Layout.touch,
                      ),
                      child: Center(
                        child: Text(
                          'Batal',
                          style: StabiloType.label.copyWith(color: c.ink),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: switch (s.phase) {
                BookSearchPhase.checking => const SizedBox.shrink(),
                BookSearchPhase.preparing => _Preparing(state: s),
                BookSearchPhase.idle => _Recents(
                  recents: s.recents,
                  onPick: (q) {
                    _controller.value = TextEditingValue(
                      text: q,
                      selection: TextSelection.collapsed(offset: q.length),
                    );
                    _vm.searchNow(q);
                  },
                  onClear: _vm.clearRecents,
                ),
                BookSearchPhase.results => _Results(
                  controller: _scroll,
                  result: s.result,
                  currentChapterId: widget.currentChapterId,
                  bottomInset: media.viewInsets.bottom > 0
                      ? 0
                      : media.padding.bottom,
                  onTap: (hit) => _pick(s, hit),
                ),
                BookSearchPhase.empty => _Message(
                  icon: AppIcons.searchOff,
                  title: 'Gak ketemu “${s.query.trim()}” di buku ini',
                  body: 'Cek ejaannya, atau coba kata lain.',
                ),
                BookSearchPhase.failed => const _Message(
                  icon: AppIcons.alert,
                  title: 'Pencariannya lagi macet',
                  body: 'Tutup terus buka lagi ya.',
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Layar 1: "Terakhir dicari" + baris riwayat. Kosong = gak ada apa-apa.
class _Recents extends StatelessWidget {
  const _Recents({
    required this.recents,
    required this.onPick,
    required this.onClear,
  });

  final List<String> recents;
  final ValueChanged<String> onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (recents.isEmpty) return const SizedBox.shrink();
    final c = context.stabilo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.s1, Space.s1, Space.s1, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Terakhir dicari',
                style: StabiloType.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: c.ink2,
                ),
              ),
              Semantics(
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClear,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: Layout.touch),
                    child: Center(
                      child: Text(
                        'Hapus',
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
        ),
        for (final (i, q) in recents.indexed)
          Semantics(
            button: true,
            child: InkWell(
              onTap: () => onPick(q),
              child: Container(
                constraints: const BoxConstraints(minHeight: Layout.touch),
                padding: const EdgeInsets.symmetric(horizontal: Space.s1),
                decoration: BoxDecoration(
                  border: i == recents.length - 1
                      ? null
                      : Border(bottom: BorderSide(color: c.menuLine)),
                ),
                child: Row(
                  spacing: Space.s3,
                  children: [
                    AppIcon(AppIcons.clock, size: 18, color: c.ink2),
                    Expanded(
                      child: Text(
                        q,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
          ),
      ],
    );
  }
}

/// Layar 2–3: jumlah, lalu hasil digrup per bab.
class _Results extends StatelessWidget {
  const _Results({
    required this.controller,
    required this.result,
    required this.currentChapterId,
    required this.bottomInset,
    required this.onTap,
  });

  final ScrollController controller;
  final BookSearchResult result;
  final int? currentChapterId;
  final double bottomInset;
  final ValueChanged<BookSearchHit> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final rows = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.s1, 2, Space.s1, 0),
        child: Text(
          result.countLabel,
          style: StabiloType.caption.copyWith(
            fontWeight: FontWeight.w600,
            color: c.ink2,
          ),
        ),
      ),
      for (final chapter in result.chapters) ...[
        SearchGroupHeader(
          title: chapter.title,
          count: chapter.hits.length,
          current: chapter.chapterId == currentChapterId,
        ),
        for (final (i, hit) in chapter.hits.indexed) ...[
          if (i > 0)
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: Space.s3),
              color: c.menuLine,
            ),
          SearchHitTile(
            snippet: hit.snippet,
            matchStart: hit.matchStart,
            matchEnd: hit.matchEnd,
            onTap: () => onTap(hit),
          ),
        ],
      ],
      if (result.truncated)
        Padding(
          padding: const EdgeInsets.all(Space.s4),
          child: Text(
            'Kebanyakan, coba kata yang lebih spesifik',
            textAlign: TextAlign.center,
            style: StabiloType.caption.copyWith(color: c.ink2),
          ),
        ),
    ];
    return EdgeFadeScroll(
      child: ListView(
        controller: controller,
        padding: EdgeInsets.only(bottom: bottomInset + Space.s4),
        children: rows,
      ),
    );
  }
}

/// Layar 4 (gak ketemu) dan state error.
class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body});

  final List<List<dynamic>> icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 50, 12, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.s3,
          children: [
            Container(
              width: Layout.searchTile,
              height: Layout.searchTile,
              decoration: BoxDecoration(
                color: c.muted,
                borderRadius: BorderRadius.circular(Radii.lg),
              ),
              child: Center(child: AppIcon(icon, size: 28, color: c.ink)),
            ),
            Semantics(
              header: true,
              liveRegion: true,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: StabiloType.titleSm.copyWith(color: c.ink),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(
                body,
                textAlign: TextAlign.center,
                style: StabiloType.body.copyWith(
                  fontSize: 15,
                  height: 1.5,
                  color: c.ink2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Layar 5: index buku lama lagi diisi (sekali aja per buku).
class _Preparing extends StatelessWidget {
  const _Preparing({required this.state});

  final BookSearchState state;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final fraction = state.prepareFraction;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.s2, 58, Space.s2, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.s3,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                'Nyiapin pencarian…',
                textAlign: TextAlign.center,
                style: StabiloType.titleSm.copyWith(color: c.ink),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 290),
              child: Text(
                'Cuma sekali buat buku ini. Abis ini nyarinya langsung kilat.',
                textAlign: TextAlign.center,
                style: StabiloType.body.copyWith(
                  fontSize: 15,
                  height: 1.5,
                  color: c.ink2,
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Padding(
                padding: const EdgeInsets.only(top: Space.s2),
                child: Row(
                  spacing: 10,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          height: 8,
                          child: LinearProgressIndicator(
                            value: fraction,
                            minHeight: 8,
                            backgroundColor: c.track,
                            color: c.progressFill,
                          ),
                        ),
                      ),
                    ),
                    Text(
                      '${(fraction * 100).round()}%',
                      style: StabiloType.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (state.totalChapters > 0)
              Text(
                state.prepareLabel,
                style: StabiloType.caption.copyWith(
                  fontWeight: FontWeight.w500,
                  color: c.ink2,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
