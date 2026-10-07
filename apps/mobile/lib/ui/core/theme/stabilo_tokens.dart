import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'stabilo_theme.dart';

/// Spacing, grid 4pt (board Foundations · 03 Ruang, bentuk & gerak).
abstract final class Space {
  static const s1 = 4.0; // ikon & teks kecil
  static const s2 = 8.0; // tag ke isi, antar chip
  static const s3 = 12.0; // dalam kartu
  static const s4 = 16.0; // antar section di sheet
  static const s5 = 20.0; // padding kartu
  static const s6 = 24.0; // margin layar, antar blok
  static const s8 = 32.0; // jarak besar empty state
  static const s10 = 40.0;
}

abstract final class Radii {
  static const xs = 5.0; // highlight inline
  static const sm = 12.0; // tag, chip, tile ikon
  static const md = 14.0; // cover buku, highlight grup
  static const lg = 20.0; // kartu, CTA besar
  static const xl = 28.0; // sudut atas sheet
  static const full = 999.0; // icon button, pill, segmented
  // Di luar skala Ruang, dipake board Komponen 04.
  static const field = 16.0; // field input
  static const menu = 18.0; // menu, list pengaturan
  static const dialog = 24.0;
  static const dialogIcon = 26.0; // board 22 Konfirmasi hapus (dialog + ikon)
}

/// Layout acuan iPhone 390 × 844.
abstract final class Layout {
  static const margin = Space.s6;
  static const topBar = 60.0;
  static const touch = 44.0; // target sentuh minimal
  static const icon = 20.0; // ikon di tombol (18–20)
  static const iconStroke = 1.8; // 2.2 kalau ikon ≤14
  static const outline = 1.5; // cuma di objek yang bisa dipegang
  static const shelfMinColumns = 3;
  static const shelfMinCard = 96.0; // di bawah ini kolom dikurangin
  static const shelfGapX = 14.0;
  static const shelfGapY = 24.0; // board Rak: stiker nongol 11 di bawah cover
  static const rowHeight = 84.0; // tampilan list
  static const rowGap = 4.0;
  static const barMin = 44.0; // header rak pas nyusut (maks = topBar)
  static const barShrink = 52.0; // jarak scroll buat nyusut penuh
  static const coverAspect = 2 / 3;

  /// Kolom rak: max(3, floor((lebar − 2×margin + gap) / (96 + gap))). [width]
  /// = lebar area isi (layar − 2×margin). Rumus yang sama buat landscape/iPad.
  static int shelfColumns(double width) => math.max(
    shelfMinColumns,
    ((width + shelfGapX) / (shelfMinCard + shelfGapX)).floor(),
  );
  static const sheetPadding = EdgeInsets.fromLTRB(24, 10, 24, 34);
}

/// Durasi & curve. Kalau iOS "Kurangi gerakan" nyala
/// (`MediaQuery.disableAnimationsOf`): shimmer, titik, kursor berhenti; sheet
/// jadi fade [reducedFade].
abstract final class Motion {
  static const sheetOpen = Duration(milliseconds: 280);
  static const sheetOpenCurve = Curves.easeOutCubic;
  static const sheetClose = Duration(milliseconds: 200);
  static const sheetCloseCurve = Curves.easeInCubic;
  static const highlight = Duration(milliseconds: 150);
  static const highlightCurve = Curves.easeOut;
  static const shimmer = Duration(milliseconds: 1400); // linear, loop
  static const cursorBlink = Duration(milliseconds: 1000); // steps(1)
  static const thinkingDots = Duration(milliseconds: 1200); // easeInOut, loop
  static const reducedFade = Duration(milliseconds: 150);
  static const contentFade = Duration(milliseconds: 200); // isi bab muncul
  static const toast = Duration(milliseconds: 2500); // ilang sendiri
  static const toastLong = Duration(
    seconds: 6,
  ); // toast yang ada catatan + aksi
  static const capsule = Duration(milliseconds: 200); // easeOut, kapsul baca
  static const edgeFade = Duration(milliseconds: 150); // fade tepi scroll
  static const capsuleIntro = Duration(milliseconds: 2500); // abis lanjut baca
  static const flash = Duration(milliseconds: 1200); // stabilo 0 → 60% → 0
  static const flashReduced = Duration(seconds: 3); // garis kiri 4pt
}

/// Bayangan. Default flat (tanpa bayangan).
abstract final class Elevation {
  /// CTA utama, cuma di mode terang.
  static List<BoxShadow> press(StabiloColors c, Brightness b) =>
      b == Brightness.light
      ? [BoxShadow(color: c.outline, offset: const Offset(0, 2))]
      : const [];

  /// Kapsul halaman baca: terang garis + bayangan tekan 2 + bayangan lembut,
  /// gelap bayangan lembut doang.
  static List<BoxShadow> capsule(StabiloColors c, Brightness b) =>
      b == Brightness.light
      ? [
          BoxShadow(color: c.outline, offset: const Offset(0, 2)),
          const BoxShadow(
            color: Color(0x1A1A1A1A), // 10%
            offset: Offset(0, 10),
            blurRadius: 24,
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x73000000), // 45%
            offset: Offset(0, 10),
            blurRadius: 28,
          ),
        ];

  /// Pilihan terpilih di segmented control, cuma di mode terang.
  static List<BoxShadow> segment(Brightness b) => b == Brightness.light
      ? const [
          BoxShadow(
            color: Color(0x261A1A1A), // 15%
            offset: Offset(0, 1),
            blurRadius: 3,
          ),
        ]
      : const [];

  static const toast = [
    BoxShadow(color: Color(0x2E000000), offset: Offset(0, 8), blurRadius: 24),
  ];

  static const cover = [
    BoxShadow(color: Color(0x14000000), offset: Offset(0, 4), blurRadius: 12),
  ];

  static List<BoxShadow> sheet(Brightness b) => [
    BoxShadow(
      color: b == Brightness.light
          ? const Color(0x1F000000) // 12%
          : const Color(0x4D000000), // 30%
      offset: const Offset(0, -8),
      blurRadius: 30,
    ),
  ];
}

/// Cover default (board "Cover default · aturan generate"): warna dari
/// `coverIndex(judul)`. Gelap = terang dicampur 28% `#22201C`. Teks cover
/// selalu [coverInk]; coretan stabilo pake accent, kecuali di cover kuning
/// (indeks 0) pake pink.
const coverPalette = [
  (light: Color(0xFFFFE38A), dark: Color(0xFFC1AC6B)), // kuning
  (light: Color(0xFFFFC2D3), dark: Color(0xFFC195A0)), // pink
  (light: Color(0xFFFFB27D), dark: Color(0xFFC18962)), // peach
  (light: Color(0xFFA6E6C6), dark: Color(0xFF81AF96)), // mint
  (light: Color(0xFFA3B5FF), dark: Color(0xFF7F8BBF)), // periwinkle
  (light: Color(0xFFD4B8FF), dark: Color(0xFFA28DBF)), // lilac
  (light: Color(0xFF9FDCF2), dark: Color(0xFF7CA7B6)), // langit
  (light: Color(0xFFC9DB9A), dark: Color(0xFF9AA777)), // sage
];
const coverInk = Color(0xFF1A1A1A);
const coverInk2 = Color(0xC71A1A1A); // penulis, 78%
