import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'stabilo_theme.dart';

/// Spacing, 4pt grid (board Foundations · 03 Ruang, bentuk & gerak).
abstract final class Space {
  static const s1 = 4.0; // icons & small text
  static const s2 = 8.0; // tag to content, between chips
  static const s3 = 12.0; // inside cards
  static const s4 = 16.0; // between sections in a sheet
  static const s5 = 20.0; // card padding
  static const s6 = 24.0; // screen margin, between blocks
  static const s8 = 32.0; // large gap in empty states
  static const s10 = 40.0;
}

abstract final class Radii {
  static const xs = 5.0; // inline highlight
  static const sm = 12.0; // tag, chip, icon tile
  static const md = 14.0; // book cover, group highlight
  static const lg = 20.0; // card, large CTA
  static const xl = 28.0; // top corners of a sheet
  static const full = 999.0; // icon button, pill, segmented
  // Outside the Ruang scale, used by board Komponen 04.
  static const chatTail = 6.0;
  static const chatComposer = 26.0; // chat input capsule
  static const field = 16.0; // input field
  static const menu = 18.0; // menu, settings list
  static const dialog = 24.0;
  static const dialogIcon = 26.0; // board 22 Konfirmasi hapus (dialog + icon)
  static const calendarDay = 3.0; // Statistik baca calendar square
}

/// The Statistik baca reading calendar (not on a board).
abstract final class Calendar {
  static const day = 12.0; // one day's square
  static const gap = 3.0; // between squares
}

/// Reference layout: iPhone 390 × 844.
abstract final class Layout {
  static const readerChatWidth = 120.0;
  static const readerProgressWidth = 210.0;
  static const readerProgressTrack = 40.0;
  static const readerChatProgressTrack = 72.0;
  static const chatFollowDistance = 80.0;
  static const chatHeader = 52.0;
  static const chatComposer = 52.0;
  static const chatSend = 42.0;
  static const chatSteps = 40.0; // "Langkah AI" status row + "Jawab sekarang"
  static const chatComposerBox = 55.0; // 52 capsule + 1.5 × 2 border
  static const chatBubbleFraction = 0.82;
  static const chatBubblePadding = EdgeInsets.symmetric(
    horizontal: 14,
    vertical: 10,
  );
  static const chatSheetHeight = 1 - 120 / 844;
  static const chatTextWidth = 680.0;
  static const margin = Space.s6;
  static const topBar = 60.0;
  static const touch = 44.0; // minimum touch target
  static const searchField = 44.0; // SearchField of the Cari kata sheet
  static const searchRing = 4.0; // SearchField focus ring
  static const searchSheetTop = 54.0; // Cari kata sheet: top offset
  static const searchNavHeight = 50.0; // result navigator, full
  static const searchNavCompactHeight = 46.0; // navigator, shrunk on scroll
  static const searchNavButton = 36.0; // nav button circle (tap 44)
  static const searchNavDivider = 24.0; // divider before ×
  static const searchClear = 22.0; // × in SearchField
  static const searchTile = 64.0; // icon of the "not found" screen
  static const searchDot = 10.0; // yellow dot on ⋯ in search mode
  static const readerMenuWidth = 232.0; // ⋯ menu popover on the capsule
  static const readerMenuRow = 50.0; // ⋯ menu row
  static const icon = 20.0; // icon inside buttons (18–20)
  static const iconStroke = 1.8; // 2.2 when the icon is ≤14
  static const outline = 1.5; // only on tangible objects
  static const shelfMinColumns = 3;
  static const shelfMinCard = 96.0; // below this, columns are reduced
  static const shelfGapX = 14.0;
  static const shelfGapY = 24.0; // sticker sticks out 11 below cover
  static const rowHeight = 84.0; // list view
  static const rowGap = 4.0;
  static const chapterBarGap = 3.0; // gap between list strip slots
  static const chapterBarHeight = 4.0; // height of the progress bar in the list
  static const barMin = 44.0; // shelf header when shrunk (max = topBar)
  static const barShrink = 52.0; // scroll distance to shrink fully
  static const coverAspect = 2 / 3;
  // Chapter start (board 03 Baca + "awal bab, judul panjang").
  static const chapterOpenerTop = 40.0;
  static const chapterOpenerBottom = 28.0;
  static const chapterOpenerGap = 14.0;
  static const chapterStrokeWidth = 56.0; // slanted yellow stroke
  static const chapterStrokeHeight = 8.0;
  static const chapterStrokeTilt = -4 * math.pi / 180;

  /// Shelf columns: max(3, floor((width − 2×margin + gap) / (96 + gap))).
  /// [width] = content area width (screen − 2×margin). Same for landscape/iPad.
  static int shelfColumns(double width) => math.max(
    shelfMinColumns,
    ((width + shelfGapX) / (shelfMinCard + shelfGapX)).floor(),
  );
  static const sheetPadding = EdgeInsets.fromLTRB(24, 10, 24, 34);

  // "Masuk ke buku mana?" sheet (board Import Markdown).
  static const pickRow = 62.0; // cover 48 + 2 × 7
  static const pickCover = 48.0; // height of the mini cover in a row
  static const pickRadio = 24.0;
  static const pickFade = 28.0; // fade of the peeking list
  static const pickVisibleRows = 3; // fully visible rows, the rest scrolls
  static const pickSheetHeight = 1 - 72 / 844; // sheet top at 72 of 844

  // "Artinya" sheet (board "Ngumpet pas scroll", 844 screen).
  static const artinyaHeight = 528 / 844; // fixed fraction of the screen
  static const artinyaHeader = 91.0; // grabber + title + X + gap
  static const artinyaActions = 102.0; // 52 button + 16 gap + 34 safe area
  static const artinyaGrabberZone = 12.0; // content fade starts here
  static const sheetDismissFling = 700.0; // downward fling (pt/s) that closes
  static const sheetDismissRatio = 0.75; // or drag until this fraction remains

  // Sheet → yellow card content sync.
  static const followGap = Space.s6; // below active paragraph → sheet top

  // Bedahin screen (board Bedahin · Opsi C).
  static const breakdownHeader = 48.0; // back + title + book · chapter
  static const breakdownPanel = 0.4; // text panel max fraction of the screen
  static const breakdownBadge = 20.0; // section number in text (min, ×Aa)
  static const breakdownNumber = 28.0; // section number in the explanation
  static const breakdownGutter = 20.0; // ¶n column in the text panel
  static const breakdownReadLine = 96.0; // reading line from explanation top
  static const breakdownSwitch = 24.0; // active-section switch hysteresis
  static const breakdownFolded = 52.0; // text panel when folded
  static const breakdownFoldStrip = 28.0; // fold chevron at the panel edge

  // Book long-press menu (board 20 Tekan lama buku, 390 × 844 screen).
  static const bookMenuTop = 168.0; // lifted cover top, from screen top
  static const bookMenuCover = 156.0; // width of the lifted cover
  // 3-column card at 390: lifted cover = that card scaled by 156 / this.
  static const bookMenuCoverSource = (390 - 2 * margin - 2 * shelfGapX) / 3;
  static const bookMenuGap = 18.0; // cover → menu panel
  static const bookMenuWidth = 250.0;
  static const bookMenuRow = 52.0;
  static const bookMenuBlur = 8.0; // shelf blur sigma

  // NavBar bottom bar (board Komponen · NavBar).
  static const navBar = 60.0; // floating pill
  static const navTab = 48.0; // active tab pill / idle tab circle
  static const navBottom = 26.0; // from screen bottom (above home bar)
  static const navSpace = 104.0; // space below content, behind the bar
  static const navBadge = 16.0; // download badge on the Cari buku tab
  static const navChip = 44.0; // "Ngunduh N buku" chip
  static const navChipGap = 12.0; // chip → bar
  static const navChipRing = 28.0;
}

/// Durations & curves. When iOS "Reduce Motion" is on
/// (`MediaQuery.disableAnimationsOf`): shimmer, dots, cursor stop; sheets
/// become a [reducedFade] fade.
abstract final class Motion {
  static const sheetOpen = Duration(milliseconds: 280);
  static const sheetOpenCurve = Curves.easeOutCubic;
  static const sheetClose = Duration(milliseconds: 200);
  static const sheetCloseCurve = Curves.easeInCubic;
  static const follow = Duration(
    milliseconds: 70,
  ); // easeOut, tracks the finger, light
  static const riseCurve = Curves.easeInOutCubic; // starts & stops gently

  /// Page rise when the Artinya sheet opens: the farther, the longer
  /// (0.6 ms per pt, 280–520 ms), so a paragraph in the middle doesn't jerk.
  static Duration rise(double distance) => Duration(
    milliseconds: (distance.abs() * 0.6).clamp(280.0, 520.0).round(),
  );
  static const highlight = Duration(milliseconds: 150);
  static const highlightCurve = Curves.easeOut;
  static const shimmer = Duration(milliseconds: 1400); // linear, loop
  static const cursorBlink = Duration(milliseconds: 1000); // steps(1)
  static const thinkingDots = Duration(milliseconds: 1200); // easeInOut, loop
  static const reducedFade = Duration(milliseconds: 150);
  static const navTab = Duration(milliseconds: 200); // pill slide + label
  static const progressStep = Duration(milliseconds: 150); // number + bar
  static const importMin = Duration(milliseconds: 1500); // min import loading
  static const importSettle = Duration(milliseconds: 300); // pause at 100%
  static const contentFade = Duration(milliseconds: 200); // chapter fades in
  static const toast = Duration(milliseconds: 2500); // disappears on its own
  static const toastBaca = Duration(seconds: 5); // Markdown import + Baca toast
  static const toastLong = Duration(seconds: 6); // toast with a note + action
  static const capsule = Duration(milliseconds: 200); // easeOut, capsule
  static const sheetChrome = Duration(
    milliseconds: 200,
  ); // easeOut, sheet button
  static const edgeFade = Duration(milliseconds: 150); // scroll edge fade
  static const capsuleIntro = Duration(milliseconds: 2500); // after resume
  static const flash = Duration(milliseconds: 1200); // stabilo 0 → 60% → 0
  static const flashReduced = Duration(seconds: 3); // 4pt left line
  static const searchFlash = Duration(
    milliseconds: 600,
  ); // Cari kata result paragraph blinks muted
  static const searchRegrow = Duration(
    milliseconds: 1200,
  ); // navigator returns to full after scrolling stops
  static const searchPill = Duration(
    milliseconds: 150,
  ); // navigator full ↔ shrunk (width)
  static const searchToast = Duration(seconds: 6); // "Balik ke posisi tadi?"
  static const writingDots = Duration(milliseconds: 1600); // "Lagi nulis" dots
  static const stepPulse = Duration(
    milliseconds: 600,
  ); // Langkah AI dot, back and forth
  static const tailFade = Duration(milliseconds: 300); // text end turns solid
  static const statusSwap = Duration(milliseconds: 150); // status → "Salin"
  static const jump = Duration(milliseconds: 300); // jump to section
  static const fold = Duration(milliseconds: 200); // Bedahin panel folding
}

/// Shadows. Default is flat (no shadow).
abstract final class Elevation {
  /// Main CTA, light mode only.
  static List<BoxShadow> press(StabiloColors c, Brightness b) =>
      b == Brightness.light
      ? [BoxShadow(color: c.outline, offset: const Offset(0, 2))]
      : const [];

  /// Reading page capsule: light has a line + a pressed shadow 2 + a soft
  /// shadow, dark has only the soft shadow.
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

  /// Selected option in the segmented control, light mode only.
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

  /// Lifted cover in the long-press menu (same in light & dark).
  static const lift = [
    BoxShadow(color: Color(0x38000000), offset: Offset(0, 14), blurRadius: 28),
  ];

  /// Long-press menu panel.
  static const menu = [
    BoxShadow(color: Color(0x38000000), offset: Offset(0, 16), blurRadius: 40),
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

/// Default cover (board "Cover default · aturan generate"): color from
/// `coverIndex(title)`. Dark = light mixed with 28% of the ink color 0x22201C. Cover text is
/// always [coverInk]; the stabilo stroke uses accent, except on the yellow cover
/// (index 0), which uses pink.
const coverPalette = [
  (light: Color(0xFFFFE38A), dark: Color(0xFFC1AC6B)), // yellow
  (light: Color(0xFFFFC2D3), dark: Color(0xFFC195A0)), // pink
  (light: Color(0xFFFFB27D), dark: Color(0xFFC18962)), // peach
  (light: Color(0xFFA6E6C6), dark: Color(0xFF81AF96)), // mint
  (light: Color(0xFFA3B5FF), dark: Color(0xFF7F8BBF)), // periwinkle
  (light: Color(0xFFD4B8FF), dark: Color(0xFFA28DBF)), // lilac
  (light: Color(0xFF9FDCF2), dark: Color(0xFF7CA7B6)), // sky
  (light: Color(0xFFC9DB9A), dark: Color(0xFF9AA777)), // sage
];
const coverInk = Color(0xFF1A1A1A);
const coverInk2 = Color(0xC71A1A1A); // author, 78%
