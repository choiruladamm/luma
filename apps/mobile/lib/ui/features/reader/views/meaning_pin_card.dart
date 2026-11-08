import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../domain/models/book.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';

/// Card kuning tetap pas sheet Artinya kebuka (halaman gak geser): jendela di
/// posisi grup, isinya teks grup yang di-scroll ngikutin seberapa jauh
/// terjemahan kebaca. Dipasang cuma kalau grupnya kepanjangan (bawah teksnya
/// ketutup sheet): yang muat gak ada yang perlu di-scroll.
///
/// Dipasang di Stack yang sama dengan teks bab (koordinat [show] = koordinat
/// Stack itu). Kosong sampai [MeaningPinCardState.show] dipanggil.
class MeaningPinCard extends StatefulWidget {
  const MeaningPinCard({
    super.key,
    required this.marginWidth,
    required this.gap,
    required this.style,
  });

  final double marginWidth;

  /// Jarak antar paragraf.
  final double gap;

  /// Gaya teks di atas highlight.
  final TextStyle style;

  @override
  State<MeaningPinCard> createState() => MeaningPinCardState();
}

class MeaningPinCardState extends State<MeaningPinCard> {
  ({Rect rect, List<ReaderParagraph> paras})? _pin;
  final _scroll = ScrollController();
  final _view = GlobalKey();
  final _keys = <int, GlobalKey>{};
  Future<void>? _unpinning;

  void show(Rect rect, List<ReaderParagraph> paras) =>
      setState(() => _pin = (rect: rect, paras: paras));

  /// Tutup card tetap: isinya balik ke awal dulu biar gak loncat ke teks
  /// halaman di bawahnya. Dipanggil dua kali (sheet mulai nutup, sheet udah
  /// hilang) nunggu proses yang sama.
  Future<void> unpin({bool animate = true}) => _pin == null
      ? Future.value()
      : _unpinning ??= _unpin(animate).whenComplete(() => _unpinning = null);

  Future<void> _unpin(bool animate) async {
    if (animate && _scroll.hasClients && _scroll.offset > 0.5) {
      await _scroll.animateTo(
        0,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : Motion.sheetClose,
        curve: Curves.easeOut,
      );
    }
    if (mounted) setState(() => _pin = null);
  }

  /// Sinkron sheet → card: [progress] (0–1) = seberapa jauh terjemahan kebaca.
  /// 0 = posisi awal, 1 = bawah teks grup tepat [Layout.followGap] di atas
  /// sheet. Di antaranya linear, dikejar dengan animasi pendek.
  void follow(double progress, double sheetTop) {
    final view = _view.currentContext?.findRenderObject();
    final pin = _pin;
    final last = pin == null
        ? null
        : _keys[pin.paras.last.index]?.currentContext?.findRenderObject();
    if (view is! RenderBox || last is! RenderBox || !_scroll.hasClients) {
      return;
    }
    final viewTop = view.localToGlobal(Offset.zero).dy;
    final shown =
        sheetTop - Layout.followGap - viewTop; // tinggi yang kelihatan
    final textBottom =
        last.localToGlobal(Offset.zero).dy -
        viewTop +
        _scroll.offset +
        last.size.height;
    final needed = (textBottom - shown).clamp(0.0, double.infinity);
    final target = (progress * needed).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
      return;
    }
    // Dikejar halus, bukan loncat: tiap update restart animasi pendek dari
    // posisi sekarang, jadi fling di sheet gak bikin teks tersentak.
    unawaited(
      _scroll.animateTo(target, duration: Motion.follow, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pin = _pin;
    if (pin == null) {
      // Stack induk cuma boleh isi Positioned: ukurannya gak ikut kena.
      return const Positioned(width: 0, height: 0, child: SizedBox.shrink());
    }
    final c = context.stabilo;
    return Positioned.fromRect(
      key: const ValueKey('pinned-group'),
      rect: pin.rect,
      child: IgnorePointer(
        child: ClipRRect(
          key: _view,
          // Bawahnya lurus: kartu terus ke bawah sheet, nyatu sama card
          // halaman, bukan kotak yang berhenti di atas sheet.
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Radii.md),
          ),
          // Canvas dulu: highlight gelap tembus pandang, tanpa ini teks
          // halaman di belakangnya kelihatan dobel.
          child: ColoredBox(
            color: c.canvas,
            child: ColoredBox(
              color: c.highlight,
              child: SingleChildScrollView(
                controller: _scroll,
                physics: const NeverScrollableScrollPhysics(),
                // Bawah selebar jarak ke sheet: paragraf terakhir bisa naik
                // sampe kelihatan penuh di atas sheet.
                padding: EdgeInsets.fromLTRB(
                  widget.marginWidth / 2,
                  Space.s2,
                  widget.marginWidth / 2,
                  Layout.followGap,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: widget.gap,
                  children: [
                    for (final p in pin.paras)
                      KeyedSubtree(
                        key: _keys.putIfAbsent(p.index, GlobalKey.new),
                        child: Text(p.text, style: widget.style),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
