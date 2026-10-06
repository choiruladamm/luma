import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/cover.dart';
import 'package:luma/ui/core/widgets/book_cover.dart';

import '../../app.dart';

void main() {
  setUpAll(() async {
    // Tests render with Ahem unless the real font is loaded.
    await (FontLoader('Bricolage Cover')..addFont(
          rootBundle.load('assets/fonts/BricolageGrotesque-Variable.ttf'),
        ))
        .load();
  });

  // Grid cover width from the board; examples are its "Contoh" row.
  const w = 104.67;
  // Records compare lists by identity, so lines are joined with " / ".
  String lay(String title) {
    final t = layoutCoverTitle(title, w, measureCoverText);
    return '${t.fontSize.toStringAsFixed(1)} · ${t.width.round()} · '
        '${t.lines.map((l) => l.text).join(' / ')}';
  }

  test('board examples pick the same step and lines', () {
    expect(lay('Emma'), '16.7 · 100 · EMMA');
    expect(lay('Pride and Prejudice'), '14.7 · 100 · PRIDE AND / PREJUDICE');
    expect(lay('Frankenstein'), '14.7 · 75 · FRANKENSTEIN');
    expect(
      lay('The Adventures of Sherlock Holmes'),
      // The board wraps "ADVENTURES / OF SHERLOCK": the browser measures a
      // hair wider. Same step, same rule, words intact.
      '14.7 · 75 · THE / ADVENTURES OF / SHERLOCK / HOLMES',
    );
    expect(
      lay('Sapiens: A Brief History of Humankind'),
      '16.7 · 100 · SAPIENS',
    );
    expect(
      lay('The Life and Opinions of Tristram Shandy, Gentleman'),
      '12.6 · 75 · THE LIFE AND / OPINIONS OF / TRISTRAM / SHANDY, / GENTLEMAN',
    );
  });

  test('board edge cases: shrunk word, cut title', () {
    final word = layoutCoverTitle(
      'Supercalifragilisticexpialidocious',
      w,
      measureCoverText,
    );
    expect(word.fontSize, closeTo(9.6, 0.05));
    expect(word.lines.single.fontSize, lessThan(word.fontSize));

    final long = layoutCoverTitle(
      'A very long title that keeps going on and on without ever really '
      'stopping anywhere because the author simply refuses to end it',
      w,
      measureCoverText,
    );
    expect(long.lines, hasLength(6));
    expect(long.lines.last.text, endsWith('…'));
  });

  testWidgets('default cover shows title, author and band space', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const BookCover(
        title: 'Pride and Prejudice',
        author: 'Jane Austen',
        width: w,
        progress: 0.34,
      ),
    );
    expect(find.text('PRIDE AND'), findsOneWidget);
    expect(find.text('PREJUDICE'), findsOneWidget);
    expect(find.text('Jane Austen'), findsOneWidget);
    final size = tester.getSize(find.byType(BookCover));
    expect(size.width, closeTo(w, 1e-6));
    expect(size.height, closeTo(w * 1.5, 1e-6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mini cover shows only the initial', (tester) async {
    await pumpApp(
      tester,
      const BookCover(title: 'The Picture of Dorian Gray', width: 48),
    );
    expect(find.text('P'), findsOneWidget);
    expect(find.textContaining('DORIAN'), findsNothing);
  });

  testWidgets('broken or tiny cover files fall back to the default', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('luma_cover_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final broken = File('${dir.path}/broken.jpg')..writeAsBytesSync([1, 2, 3]);
    // 1×1 transparent PNG: decodes fine but is under 200px.
    final tiny = File('${dir.path}/tiny.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==',
        ),
      );

    for (final file in [broken, tiny]) {
      // File reads and decoding need the real event loop.
      await tester.runAsync(() async {
        await pumpApp(
          tester,
          BookCover(key: ValueKey(file), title: 'Emma', width: w, file: file),
        );
        await Future<void>.delayed(const Duration(seconds: 1));
      });
      await tester.pump();
      expect(find.text('EMMA'), findsOneWidget, reason: file.path);
    }
  });
}
