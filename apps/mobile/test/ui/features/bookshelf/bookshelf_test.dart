import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/models/book.dart';
import 'package:luma/main.dart';
import 'package:luma/ui/core/widgets/book_card.dart';
import 'package:luma/ui/features/bookshelf/view_models/bookshelf_view_model.dart';
import 'package:luma/ui/features/reader/views/reader_view.dart';
import 'package:luma/ui/features/settings/views/settings_view.dart';

ShelfBook book(int id, String title, {bool opened = false}) => ShelfBook(
  id: id,
  title: title,
  author: 'Somebody',
  coverName: null,
  opened: opened,
);

void main() {
  // The shelf is fed by a controller, not Drift: widget tests run on a fake
  // clock and Drift streams need the real one (they hang). The Drift side is
  // covered in test/data/book_repository_test.dart.
  late StreamController<List<ShelfBook>> shelf;
  setUp(() => shelf = StreamController());
  tearDown(() => shelf.close());

  Future<void> pump(
    WidgetTester tester,
    List<ShelfBook> books, {
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [booksStreamProvider.overrideWith((ref) => shelf.stream)],
        child: const LumaApp(),
      ),
    );
    shelf.add(books);
    await tester.pump();
  }

  for (final b in Brightness.values) {
    testWidgets('empty shelf invites an import ($b)', (tester) async {
      await pump(tester, [], brightness: b);
      expect(find.text('Rak buku lo'), findsOneWidget);
      expect(find.text('Import EPUB'), findsOneWidget);
      expect(
        find.text('Ambil dari app Files, format .epub aja'),
        findsOneWidget,
      );
      expect(find.byType(BookCard), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a new book shows up as soon as the shelf stream emits', (
    tester,
  ) async {
    await pump(tester, []);
    shelf.add([
      book(2, 'The Enchiridion', opened: true),
      book(1, 'Meditations'),
    ]);
    await tester.pump();

    expect(find.text('Semua buku'), findsOneWidget);
    expect(
      tester.widgetList<BookCard>(find.byType(BookCard)).map((c) => c.title),
      ['The Enchiridion', 'Meditations'],
    );
    expect(find.text('Baru'), findsOneWidget); // only the unopened one
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a book opens the reader; the gear opens settings', (
    tester,
  ) async {
    await pump(tester, [book(1, 'Meditations')]);

    await tester.tap(find.byType(BookCard));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderView), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Pengaturan app'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsView), findsOneWidget);
  });
}
