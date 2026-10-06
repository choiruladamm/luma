import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/main.dart';
import 'package:luma/ui/features/bookshelf/view_models/bookshelf_view_model.dart';

void main() {
  testWidgets('app boots into the bookshelf', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        // Widget tests never touch Drift streams (fake clock → hang).
        overrides: [
          booksStreamProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: const LumaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rak buku lo'), findsOneWidget);
  });
}
