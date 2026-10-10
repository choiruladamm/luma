import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/book_repository.dart';
import '../../../../data/services/file_storage.dart';
import '../../../../domain/luma_markdown.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/book_cover.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/edge_fade.dart';
import '../../../core/widgets/field.dart';
import '../../../core/widgets/sheet.dart';
import '../view_models/import_view_model.dart';

/// Sheet "Masuk ke buku mana?" (board Import Markdown 1–3): file `.md` tanpa
/// header lengkap. Tebakan dari [ImportMarkdownAsk.parsed] udah ngisi field.
///
/// Sheet tetap kebuka selama dialog bab dobel nongol di atasnya, jadi isian
/// utuh pas user Batal.
class ImportMarkdownSheet extends ConsumerStatefulWidget {
  const ImportMarkdownSheet({super.key, required this.ask});

  final ImportMarkdownAsk ask;

  @override
  ConsumerState<ImportMarkdownSheet> createState() =>
      _ImportMarkdownSheetState();
}

class _ImportMarkdownSheetState extends ConsumerState<ImportMarkdownSheet> {
  late final _book = TextEditingController(text: _parsed.book ?? '');
  late final _chapterTitle = TextEditingController(
    text: _parsed.chapterTitle ?? '',
  );
  late final _number = TextEditingController(text: '${_parsed.chapter ?? 1}');

  /// Buku Markdown yang dipilih; null = "Buku baru".
  MarkdownBook? _picked;
  var _saving = false;

  /// Field yang udah disentuh: error baru muncul setelah itu.
  final _touched = <String>{};

  ParsedMarkdown get _parsed => widget.ask.parsed;

  @override
  void dispose() {
    _book.dispose();
    _chapterTitle.dispose();
    _number.dispose();
    super.dispose();
  }

  void _pick(MarkdownBook? book) {
    setState(() {
      _picked = book;
      _touched.remove('number');
      _number.text = '${_parsed.chapter ?? book?.nextChapter ?? 1}';
    });
  }

  int? get _chapterNumber {
    final n = int.tryParse(_number.text.trim());
    return n != null && n > 0 ? n : null;
  }

  String? get _bookError {
    if (_picked != null || _book.text.trim().isNotEmpty) return null;
    return _touched.contains('book') ? 'Judul buku gak boleh kosong' : null;
  }

  String? get _numberError {
    if (_chapterNumber != null) return null;
    return _touched.contains('number') ? 'Harus angka' : null;
  }

  bool get _valid =>
      _chapterNumber != null &&
      (_picked != null || _book.text.trim().isNotEmpty);

  /// `book_key` buku baru: dari header kalau judulnya gak diubah, kalau
  /// enggak dari slug judul.
  // ponytail: judul tanpa huruf latin (slug kosong) pakai penanda waktu.
  // Kasih input slug eksplisit kalau ada yang pakai judul non-latin.
  String _newKey(String title) {
    if (title == _parsed.book && _parsed.bookKey != null) {
      return _parsed.bookKey!;
    }
    final slug = slugify(title);
    return slug.isEmpty
        ? 'buku-${DateTime.now().millisecondsSinceEpoch}'
        : slug;
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    final title = _book.text.trim();
    final picked = _picked;
    final chapterTitle = _chapterTitle.text.trim();
    await ref.read(importControllerProvider.notifier).submitMarkdown((
      bookId: picked?.book.id,
      bookKey: picked == null ? _newKey(title) : slugify(picked.book.title),
      bookTitle: picked?.book.title ?? title,
      author: _parsed.author,
      chapter: _chapterNumber,
      chapterTitle: chapterTitle.isEmpty ? null : chapterTitle,
    ));
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final picked = _picked;
    final canSubmit = _valid && !_saving;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SheetFrame(
        actions: [
          AppButton.secondary(
            label: 'Batal',
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: AppButton.primary(
              label: 'Masukin',
              onPressed: canSubmit ? _submit : null,
            ),
          ),
        ],
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.s2,
            children: [
              Semantics(
                header: true,
                child: Text('Masuk ke buku mana?', style: StabiloType.titleMd),
              ),
              Text(
                widget.ask.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: StabiloType.mono.copyWith(fontSize: 12, color: c.ink2),
              ),
            ],
          ),
          _BookList(
            books: widget.ask.books,
            picked: picked,
            onPick: _pick,
            coverFile: (name) =>
                name == null ? null : ref.read(fileStorageProvider).cover(name),
          ),
          if (picked == null)
            AppField(
              label: 'Judul buku',
              hint: 'Judul buku',
              controller: _book,
              mono: false,
              error: _bookError,
              onChanged: (_) => setState(() => _touched.add('book')),
            ),
          AppField(
            label: 'Judul bab',
            hint: 'Judul bab (opsional)',
            controller: _chapterTitle,
            mono: false,
          ),
          AppField(
            label: 'Nomor bab',
            controller: _number,
            mono: false,
            keyboardType: TextInputType.number,
            error: _numberError,
            helper: picked?.lastChapter == null
                ? null
                : 'Bab terakhir di buku ini: ${picked!.lastChapter}',
            onChanged: (_) => setState(() => _touched.add('number')),
          ),
          if (picked == null)
            Row(
              spacing: Space.s1 + 2,
              children: [
                AppIcon(AppIcons.info, size: 14, color: c.ink2),
                Expanded(
                  child: Text(
                    'Ditebak dari judul di file. Boleh diubah.',
                    style: StabiloType.caption.copyWith(
                      fontSize: 12.5,
                      color: c.ink2,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Radio list: "Buku baru" paling atas, lalu buku Markdown. 3 baris
/// keliatan penuh, sisanya scroll dengan baris ke-4 ngintip + fade.
class _BookList extends StatelessWidget {
  const _BookList({
    required this.books,
    required this.picked,
    required this.onPick,
    required this.coverFile,
  });

  final List<MarkdownBook> books;
  final MarkdownBook? picked;
  final ValueChanged<MarkdownBook?> onPick;
  final File? Function(String? coverName) coverFile;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      _PickRow(
        selected: picked == null,
        title: 'Buku baru',
        subtitle: 'Bikin buku dari file ini',
        leading: const _NewBookTile(),
        onTap: () => onPick(null),
      ),
      for (final b in books)
        _PickRow(
          selected: picked?.book.id == b.book.id,
          title: b.book.title,
          subtitle: b.chaptersLabel,
          leading: BookCover(
            title: b.book.title,
            width: Layout.pickCover * Layout.coverAspect,
            file: coverFile(b.book.coverName),
          ),
          onTap: () => onPick(b),
        ),
    ];
    final overflow = rows.length > Layout.pickVisibleRows;
    final list = Column(children: rows);
    if (!overflow) return list;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: Layout.pickRow * (Layout.pickVisibleRows + 0.5),
      ),
      child: EdgeFadeScroll(
        top: EdgeFadeSide.none,
        bottom: const EdgeFadeSide(Layout.pickFade),
        child: SingleChildScrollView(child: list),
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.onTap,
  });

  final bool selected;
  final String title, subtitle;
  final Widget leading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title, $subtitle',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: Layout.pickRow,
          child: Row(
            spacing: Space.s3,
            children: [
              SizedBox(width: 36, child: Center(child: leading)),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StabiloType.body.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StabiloType.caption.copyWith(
                        fontSize: 13,
                        color: c.ink2,
                      ),
                    ),
                  ],
                ),
              ),
              _Radio(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kosong = ring `fieldLine`, kepilih = accent + centang (pasangan Switch).
class _Radio extends StatelessWidget {
  const _Radio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return AnimatedContainer(
      duration: Motion.edgeFade,
      width: Layout.pickRadio,
      height: Layout.pickRadio,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? c.accent : null,
        border: Border.all(
          color: selected ? c.accentBorder : c.fieldLine,
          width: Layout.outline,
        ),
      ),
      child: selected
          ? AppIcon(AppIcons.check, size: 14, color: c.onAccent)
          : null,
    );
  }
}

/// Kotak putus-putus + ikon tambah, ganti cover buat "Buku baru".
class _NewBookTile extends StatelessWidget {
  const _NewBookTile();

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return CustomPaint(
      painter: _DashedBox(color: c.fieldLine, radius: Radii.sm / 2),
      child: SizedBox(
        width: 36,
        height: Layout.pickCover,
        child: Center(child: AppIcon(AppIcons.add, size: 18, color: c.ink2)),
      ),
    );
  }
}

class _DashedBox extends CustomPainter {
  const _DashedBox({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = Layout.outline;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 8) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBox old) =>
      old.color != color || old.radius != radius;
}
