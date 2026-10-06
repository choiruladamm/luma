import 'package:flutter/material.dart';

/// Skala teks Stabilo (board Foundations · 02 Tipografi). Tanpa warna: warna
/// ikut theme / `context.stabilo`.
// ponytail: font statis per weight, jadi optical size (opsz) Bricolage &
// Literata gak ikut ukuran. Ganti ke font variable + FontVariation kalau
// judul besar keliatan beda dari board.
abstract final class StabiloType {
  static const ui = 'Bricolage Grotesque';
  static const readingFont = 'Atkinson Hyperlegible';
  static const bookFont = 'Literata';

  // UI · Bricolage Grotesque. height = line-height px / size.
  static const display = TextStyle(
    fontFamily: ui,
    fontSize: 34,
    height: 36 / 34,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.03 * 34,
  );
  static const titleLg = TextStyle(
    fontFamily: ui,
    fontSize: 28,
    height: 31 / 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.02 * 28,
  );
  static const titleMd = TextStyle(
    fontFamily: ui,
    fontSize: 24,
    height: 28 / 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.02 * 24,
  );
  static const titleSm = TextStyle(
    fontFamily: ui,
    fontSize: 19,
    height: 23 / 19,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.01 * 19,
  );
  static const body = TextStyle(
    fontFamily: ui,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
  );
  static const label = TextStyle(
    fontFamily: ui,
    fontSize: 15,
    height: 18 / 15,
    fontWeight: FontWeight.w700,
  );
  static const caption = TextStyle(
    fontFamily: ui,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w500,
  );

  /// Teksnya di-`toUpperCase()` sendiri (TextStyle gak bisa CAPS).
  static const tag = TextStyle(
    fontFamily: ui,
    fontSize: 12,
    height: 1,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.03 * 12,
  );
  static const micro = TextStyle(
    fontFamily: ui,
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w700,
  );

  // Bacaan. Ukuran & jarak baris default; pilihan Aa menimpa lewat copyWith.
  static const reading = TextStyle(
    fontFamily: readingFont,
    fontSize: 18.5,
    height: 1.65,
  );
  static const readingBook = TextStyle(
    fontFamily: bookFont,
    fontSize: 18.5,
    height: 1.7,
  );

  /// Terjemahan di sheet artinya.
  static const readingSheet = TextStyle(
    fontFamily: readingFont,
    fontSize: 15.5,
    height: 1.5,
  );

  /// Kode error, API key, model ID.
  static const mono = TextStyle(
    fontFamily: 'Menlo',
    fontFamilyFallback: ['Courier', 'monospace'],
    fontSize: 15,
  );

  /// Mode gelap: jarak baris bacaan +0,05 (teks terang di latar gelap
  /// keliatan lebih tebel).
  static TextStyle forBrightness(TextStyle s, Brightness b) =>
      b == Brightness.dark ? s.copyWith(height: s.height! + 0.05) : s;

  /// Skala UI dipetakan ke slot Material, biar widget bawaan ikut Bricolage.
  static const textTheme = TextTheme(
    headlineLarge: display,
    headlineMedium: titleLg,
    headlineSmall: titleMd,
    titleLarge: titleSm,
    titleMedium: label,
    bodyLarge: body,
    bodyMedium: body,
    bodySmall: caption,
    labelLarge: label,
    labelMedium: caption,
    labelSmall: micro,
  );
}
