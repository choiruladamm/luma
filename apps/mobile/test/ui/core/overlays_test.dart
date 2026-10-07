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

  testWidgets('dialog with an icon: 48 tile at the left, not full width', (
    tester,
  ) async {
    await pumpApp(
      tester,
      opener(
        (context) => showConfirmDialog(
          context,
          icon: AppIcons.delete,
          title: 'Hapus "Dracula" dari rak?',
          message: 'File aslinya di Files tetep aman kok.',
          cancelLabel: 'Gak jadi',
          confirmLabel: 'Hapus',
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The panel itself (the Dialog widget spans the screen).
    final dialog = tester.getRect(
      find
          .descendant(of: find.byType(Dialog), matching: find.byType(Material))
          .first,
    );
    final tile = tester.getRect(
      find.ancestor(of: find.byType(AppIcon), matching: find.byType(Container)),
    );
    expect(tile.size, const Size(48, 48));
    expect(tile.left, dialog.left + 20); // padding, not stretched
    // Board 22: 32 off each screen edge, 50pt buttons.
    expect(dialog.width, 900 - 64);
    expect(tester.getSize(find.byType(AppButton).first).height, 50);
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

  for (final overlay in [false, true]) {
    testWidgets('copy toast pill matches the board (overlay: $overlay)', (
      tester,
    ) async {
      const msg = 'Udah disalin, tinggal paste';
      await pumpApp(
        tester,
        opener(
          (context) => overlay
              ? showOverlayToast(context, msg)
              : showToast(context, msg),
        ),
        brightness: Brightness.dark,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final text = tester.getRect(find.text(msg));
      final pill = tester.getRect(
        find
            .ancestor(of: find.text(msg), matching: find.byType(Container))
            .last,
      );
      final tick = tester.getRect(
        find
            .descendant(
              of: find.ancestor(of: find.text(msg), matching: find.byType(Row)),
              matching: find.byType(Container),
            )
            .first,
      );
      // Plain text, no debug yellow underline from a missing Material.
      final style = DefaultTextStyle.of(tester.element(find.text(msg))).style;
      expect(style.decoration, isNot(TextDecoration.underline));
      expect(
        find.ancestor(of: find.text(msg), matching: find.byType(Material)),
        findsWidgets,
      );
      expect(pill.height, 48);
      expect(tick.size, const Size(24, 24));
      expect(tick.left - pill.left, 14);
      expect(text.left - tick.right, 10);
      expect(pill.right - text.right, 18);
      expect(tick.center.dy, closeTo(pill.center.dy, 0.5));
      await tester.pump(Motion.toast); // gone by itself, either way
      await tester.pumpAndSettle();
    });
  }

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
