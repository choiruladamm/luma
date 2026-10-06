import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ui/core/theme/stabilo_tokens.dart';
import 'package:luma/ui/core/widgets/buttons.dart';
import 'package:luma/ui/core/widgets/dialog.dart';
import 'package:luma/ui/core/widgets/menu.dart';
import 'package:luma/ui/core/widgets/sheet.dart';
import 'package:luma/ui/core/widgets/toast.dart';

import '../../app.dart';

void main() {
  testWidgets('sheet shows its frame and the close button pops it', (
    tester,
  ) async {
    await pumpApp(
      tester,
      opener(
        (context) => showAppSheet<void>(
          context,
          builder: (_) => SheetFrame(
            title: 'Artinya gini nih',
            actions: [
              Expanded(
                child: AppButton.primary(label: 'Lanjut', onPressed: () {}),
              ),
            ],
            children: const [Text('isi')],
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Artinya gini nih'), findsOneWidget);
    expect(find.text('Lanjut'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Tutup'));
    await tester.pumpAndSettle();
    expect(find.text('Artinya gini nih'), findsNothing);
  });

  testWidgets('confirm dialog: Hapus → true, Batal → false', (tester) async {
    final results = <bool>[];
    await pumpApp(
      tester,
      opener(
        (context) async => results.add(
          await showConfirmDialog(
            context,
            title: 'Hapus "Dracula"?',
            message: 'Progres baca sama terjemahannya ikut kehapus.',
            confirmLabel: 'Hapus',
          ),
        ),
      ),
    );
    for (final button in ['Hapus', 'Batal']) {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
    }
    expect(results, [true, false]);
  });

  testWidgets('toast disappears by itself; its action runs once', (
    tester,
  ) async {
    var actions = 0;
    await pumpApp(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          opener((context) => showToast(context, 'Udah disalin')),
          opener(
            (context) => showToast(
              context,
              'Sip! "Walden" udah masuk rak',
              actionLabel: 'Baca',
              onAction: () => actions++,
            ),
          ),
        ],
      ),
    );
    await tester.tap(find.text('open').first);
    await tester.pumpAndSettle();
    expect(find.text('Udah disalin'), findsOneWidget);
    await tester.pump(Motion.toast);
    await tester.pumpAndSettle();
    expect(find.text('Udah disalin'), findsNothing);

    await tester.tap(find.text('open').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Baca'));
    await tester.pumpAndSettle();
    expect(actions, 1);
    expect(find.text('Baca'), findsNothing);
  });

  testWidgets('menu returns the picked value', (tester) async {
    String? picked;
    await pumpApp(
      tester,
      opener(
        (context) async =>
            picked = await showAppMenu(context, title: 'Urutin pake', [
              const AppMenuItem('recent', 'Terakhir dibuka', selected: true),
              const AppMenuItem('title', 'Judul (A–Z)'),
            ]),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Urutin pake'), findsOneWidget);
    await tester.tap(find.text('Judul (A–Z)'));
    await tester.pumpAndSettle();
    expect(picked, 'title');
  });
}
