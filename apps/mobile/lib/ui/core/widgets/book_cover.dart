import 'dart:io';

import 'package:flutter/material.dart';

import '../../../domain/cover.dart';
import '../theme/stabilo_theme.dart';
import '../theme/stabilo_tokens.dart';
import '../theme/stabilo_type.dart';

/// Cover buku rasio 2:3 (board "Cover default" & "Kartu buku"). Cover asli
/// EPUB di-crop rata atas; gak ada / rusak / < 200px → cover default dari
/// judul. [progress] non-null = pita progres di bawah cover.
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.title,
    required this.width,
    this.author,
    this.file,
    this.progress,
  });

  final String title;
  final String? author;
  final File? file;
  final double width;

  /// 0..1. Pita keisi segini; null = gak ada pita.
  final double? progress;

  /// Sudut ngikut ukuran: grid 12, kartu lanjut baca 10, list 7.
  static double radiusFor(double width) => width >= 100
      ? Radii.sm
      : width >= 64
      ? 10
      : 7;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(radiusFor(width));
    final fallback = _DefaultCover(
      title: title,
      author: author,
      width: width,
      dark: dark,
      bandSpace: progress != null,
    );

    return Container(
      width: width,
      height: width / Layout.coverAspect,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: dark ? null : Elevation.cover,
      ),
      // Garis di atas isi, biar gak ketutup cover asli.
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: c.outline, width: Layout.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (file == null) fallback else _FileCover(file!, fallback, dark),
          if (progress != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 7 + Layout.outline,
              child: _Band(progress!.clamp(0, 1), dark),
            ),
        ],
      ),
    );
  }
}

class _Band extends StatelessWidget {
  const _Band(this.progress, this.dark);

  final double progress;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xD122201C) : const Color(0xE0FFFDF6),
        border: Border(
          top: BorderSide(
            color: dark ? c.canvas : c.outline,
            width: Layout.outline,
          ),
        ),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: progress,
        heightFactor: 1,
        child: ColoredBox(color: c.accent),
      ),
    );
  }
}

/// Cover asli. Mode gelap diredupin 0.85.
class _FileCover extends StatefulWidget {
  const _FileCover(this.file, this.fallback, this.dark);

  final File file;
  final Widget fallback;
  final bool dark;

  @override
  State<_FileCover> createState() => _FileCoverState();
}

class _FileCoverState extends State<_FileCover> {
  ImageStream? _stream;
  ImageInfo? _info;
  bool _failed = false;
  late final _listener = ImageStreamListener(
    (info, _) => setState(() {
      _info?.dispose();
      _info = info;
    }),
    onError: (_, _) => setState(() => _failed = true),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_FileCover old) {
    super.didUpdateWidget(old);
    if (old.file.path != widget.file.path) _resolve();
  }

  void _resolve() {
    final stream = FileImage(widget.file)
        .resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _failed = false;
    _stream = stream..addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _info?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _info?.image;
    if (_failed || (image != null && image.width < 200)) return widget.fallback;
    if (image == null) return const SizedBox.expand();
    final cover = RawImage(
      image: image,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
    );
    if (!widget.dark) return cover;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        0.85, 0, 0, 0, 0, //
        0, 0.85, 0, 0, 0,
        0, 0, 0.85, 0, 0,
        0, 0, 0, 1, 0,
      ]),
      child: cover,
    );
  }
}

/// Style judul cover default: Bricolage variable 800, lebar huruf [width].
TextStyle coverTitleStyle(double size, double width) => TextStyle(
  fontFamily: 'Bricolage Cover',
  fontSize: size,
  height: 1.02,
  letterSpacing: -0.01 * size,
  color: coverInk,
  fontVariations: [
    const FontVariation('wght', 800),
    FontVariation('wdth', width),
    FontVariation('opsz', size.clamp(12, 96)),
  ],
);

/// Ukur pake style yang sama persis kayak yang dirender.
double measureCoverText(String text, double size, double width) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: coverTitleStyle(size, width)),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final w = painter.width;
  painter.dispose();
  return w;
}

class _DefaultCover extends StatelessWidget {
  const _DefaultCover({
    required this.title,
    required this.author,
    required this.width,
    required this.dark,
    required this.bandSpace,
  });

  final String title;
  final String? author;
  final double width;
  final bool dark;
  final bool bandSpace;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final index = coverIndex(title);
    final palette = coverPalette[index];
    final stroke = index == 0 ? c.pink : c.accent;
    final bg = dark ? palette.dark : palette.light;

    if (width < 64) {
      final size = width * 0.5;
      return ColoredBox(
        color: bg,
        child: Padding(
          padding: EdgeInsets.all(width * 0.12),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: _Stroked(
              coverInitial(title),
              style: coverTitleStyle(size, 100).copyWith(height: 0.9),
              color: stroke,
            ),
          ),
        ),
      );
    }

    final pad = width * coverPaddingFactor;
    final layout = layoutCoverTitle(title, width, measureCoverText);
    final small = TextStyle(
      fontFamily: StabiloType.ui,
      fontWeight: FontWeight.w600,
      color: coverInk2,
    );
    return ColoredBox(
      color: bg,
      child: Padding(
        padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + (bandSpace ? 9 : 0)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, line) in layout.lines.indexed)
                    i == 0
                        ? _Stroked(
                            line.text,
                            style: coverTitleStyle(line.fontSize, layout.width),
                            color: stroke,
                          )
                        : Text(
                            line.text,
                            maxLines: 1,
                            softWrap: false,
                            textScaler: TextScaler.noScaling,
                            style: coverTitleStyle(line.fontSize, layout.width),
                          ),
                  if (layout.subtitle != null)
                    Padding(
                      padding: EdgeInsets.only(top: width * 0.039),
                      child: Text(
                        layout.subtitle!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        textScaler: TextScaler.noScaling,
                        style: small.copyWith(
                          fontSize: width * 0.078,
                          height: 1.15,
                          color: coverInk,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (author != null)
              Text(
                author!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: TextScaler.noScaling,
                style: small.copyWith(fontSize: (width * 0.0764).clamp(8, 99)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Satu baris dengan coretan stabilo di 50–90% tinggi baris, melebar 0.12em
/// ke kiri-kanan.
class _Stroked extends StatelessWidget {
  const _Stroked(this.text, {required this.style, required this.color});

  final String text;
  final TextStyle style;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final bleed = 0.12 * style.fontSize!;
    return Transform.translate(
      offset: Offset(-bleed, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, color, color, Colors.transparent],
            stops: const [0.5, 0.5, 0.9, 0.9],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: bleed),
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            textScaler: TextScaler.noScaling,
            style: style,
          ),
        ),
      ),
    );
  }
}
