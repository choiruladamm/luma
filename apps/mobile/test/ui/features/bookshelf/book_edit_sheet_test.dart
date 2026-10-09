import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/book_repository.dart';
import 'package:luma/data/services/file_storage.dart';
import 'package:luma/domain/models/book.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/core/widgets/book_cover.dart';
import 'package:luma/ui/core/widgets/buttons.dart';
import 'package:luma/ui/core/widgets/switch.dart';
import 'package:luma/ui/features/bookshelf/view_models/bookshelf_view_model.dart';
import 'package:luma/ui/features/bookshelf/views/book_edit_sheet.dart';

class _Repo extends Fake implements BookRepository {
  final saved = <({String title, String? author, bool cover})>[];

  @override
  Future<void> updateMetadata(
    int id, {
    required String title,
    String? author,
    required bool useDefaultCover,
  }) async => saved.add((title: title, author: author, cover: useDefaultCover));
}

BookInfo _info({String? epubCover, String? originalTitle}) => BookInfo(
  lastOpenedAt: null,
  createdAt: DateTime(2026, 9, 12),
  fileName: null,
  fileBytes: null,
  translated: 0,
  originalTitle: originalTitle,
  originalAuthor: null,
  epubCoverName: epubCover,
);

final simpan = find.byWidgetPredicate(
  (w) => w is CircleButton && w.semanticLabel == 'Simpan',
);

void main() {
  late _Repo repo;
  setUp(() => repo = _Repo());

  Future<void> open(WidgetTester tester, BookInfo info) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookRepositoryProvider.overrideWithValue(repo),
          fileStorageProvider.overrideWithValue(
            FileStorage(Directory.systemTemp),
          ),
          booksStreamProvider.overrideWith(
            (ref) => Stream.value([
              ShelfBook(
                id: 1,
                title: 'pride_FINAL',
                author: null,
                coverName: info.epubCoverName,
                opened: false,
                createdAt: DateTime(2026, 9, 12),
              ),
            ]),
          ),
          bookInfoProvider.overrideWith((ref, id) async => info),
        ],
        child: MaterialApp(
          theme: stabiloTheme(Brightness.light),
          home: const _Gate(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('empty title: error shown and Simpan disabled', (tester) async {
    await open(tester, _info());
    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.pump();
    expect(find.text('Judul gak boleh kosong'), findsOneWidget);
    expect(tester.widget<CircleButton>(simpan).onPressed, isNull);
    await tester.tap(simpan, warnIfMissed: false);
    await tester.pump();
    expect(repo.saved, isEmpty);
  });

  testWidgets('typing updates the cover preview live', (tester) async {
    await open(tester, _info());
    await tester.enterText(find.byType(TextField).first, 'Walden');
    await tester.pump();
    final cover = tester.widget<BookCover>(find.byType(BookCover));
    expect(cover.title, 'Walden');
  });

  testWidgets('cover toggle only shows when the EPUB has a cover', (
    tester,
  ) async {
    await open(tester, _info(epubCover: 'c.jpg'));
    expect(find.text('Pakai cover default'), findsOneWidget);
    expect(find.text('Cover asli EPUB'), findsOneWidget);
    await tester.tap(find.byType(AppSwitch));
    await tester.pump();
    expect(find.text('Cover default'), findsOneWidget);
  });

  testWidgets('no EPUB cover: no cover toggle', (tester) async {
    await open(tester, _info());
    expect(find.text('Pakai cover default'), findsNothing);
  });

  testWidgets('Balikin ke aslinya refills both fields', (tester) async {
    await open(tester, _info(originalTitle: 'epub_title'));
    await tester.tap(find.text('Balikin ke aslinya'));
    await tester.pump();
    expect(find.text('epub_title'), findsWidgets);
    expect(
      find.textContaining('Dari EPUB: epub_title · tanpa penulis'),
      findsOneWidget,
    );
  });

  testWidgets('Simpan sends trimmed values; blank author is null', (
    tester,
  ) async {
    await open(tester, _info());
    await tester.enterText(find.byType(TextField).first, '  Walden ');
    await tester.enterText(find.byType(TextField).last, '   ');
    await tester.pump();
    await tester.tap(simpan);
    await tester.pump();
    expect(repo.saved.single, (title: 'Walden', author: null, cover: false));
  });
}

/// Builds the sheet only after the providers it reads once have data.
class _Gate extends ConsumerWidget {
  const _Gate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready =
        ref.watch(booksStreamProvider).hasValue &&
        ref.watch(bookInfoProvider(1)).hasValue;
    return Scaffold(
      body: ready ? const BookEditSheet(bookId: 1) : const SizedBox(),
    );
  }
}
