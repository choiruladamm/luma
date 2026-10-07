import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/core/widgets/buttons.dart';
import 'package:luma/ui/core/widgets/edge_fade.dart';
import 'package:luma/ui/core/widgets/sheet.dart';

void main() {
  Future<void> pump(WidgetTester tester, int items) => tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          height: 400,
          child: EdgeFadeScroll(
            child: ListView(
              children: [
                for (var i = 0; i < items; i++)
                  SizedBox(height: 50, child: Text('Item $i')),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  ({bool top, bool bottom}) edges(WidgetTester tester) =>
      tester.state<EdgeFadeScrollState>(find.byType(EdgeFadeScroll)).debugEdges;

  testWidgets('not scrolled yet: bottom only', (tester) async {
    await pump(tester, 30);
    await tester.pumpAndSettle();
    expect(edges(tester), (top: false, bottom: true));
  });

  testWidgets('scrolling: both', (tester) async {
    await pump(tester, 30);
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(edges(tester), (top: true, bottom: true));
  });

  testWidgets('at the bottom: top only', (tester) async {
    await pump(tester, 30);
    await tester.fling(find.byType(ListView), const Offset(0, -5000), 5000);
    await tester.pumpAndSettle();
    expect(edges(tester), (top: true, bottom: false));
  });

  testWidgets('everything fits: none', (tester) async {
    await pump(tester, 3);
    await tester.pumpAndSettle();
    expect(edges(tester), (top: false, bottom: false));
  });

  group('edgeFadeStops', () {
    const s20 = EdgeFadeSide(20);

    test('off: fully opaque everywhere', () {
      final g = edgeFadeStops(
        400,
        top: s20,
        bottom: s20,
        topOn: 0,
        bottomOn: 0,
      );
      expect(g.alphas.every((a) => a == 1), isTrue);
    });

    test('on: transparent at the edges, opaque 20pt in', () {
      final g = edgeFadeStops(
        400,
        top: s20,
        bottom: s20,
        topOn: 1,
        bottomOn: 1,
      );
      expect(g.stops, [0, 20 / 400, 1 - 20 / 400, 1]);
      expect(g.alphas, [0, 1, 1, 0]);
    });

    test('half way through the 150ms: half faded', () {
      final g = edgeFadeStops(
        400,
        top: s20,
        bottom: s20,
        topOn: 0.5,
        bottomOn: 0,
      );
      expect(g.alphas.first, 0.5);
      expect(g.alphas.last, 1);
    });

    test('no bottom fade: content runs to the edge', () {
      final g = edgeFadeStops(
        400,
        top: s20,
        bottom: EdgeFadeSide.none,
        topOn: 1,
        bottomOn: 1,
      );
      expect(g.alphas.last, 1);
      expect(g.stops.last, 1);
    });

    test('reader profile: clear band, held floor, then the fade', () {
      const top = EdgeFadeSide(48, clear: 54, hold: 64, floor: 0.18);
      final g = edgeFadeStops(
        800,
        top: top,
        bottom: EdgeFadeSide.none,
        topOn: 1,
        bottomOn: 1,
      );
      expect(g.stops.take(5), [0, 54 / 800, 54 / 800, 118 / 800, 166 / 800]);
      expect(g.alphas.take(5).map((a) => (a * 100).round() / 100), [
        0,
        0,
        0.18,
        0.18,
        1,
      ]);
    });

    test('an area shorter than both fades still has ordered stops', () {
      final g = edgeFadeStops(30, top: s20, bottom: s20, topOn: 1, bottomOn: 1);
      for (var i = 1; i < g.stops.length; i++) {
        expect(g.stops[i], greaterThanOrEqualTo(g.stops[i - 1]));
      }
      expect(g.stops.first, 0);
      expect(g.stops.last, 1);
    });
  });

  for (final withButton in [false, true]) {
    testWidgets('SheetFrame bottom edge (button: $withButton)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: stabiloTheme(Brightness.light),
          home: Scaffold(
            body: SheetFrame(
              title: 'Judul',
              actions: [
                if (withButton)
                  Expanded(
                    child: AppButton.primary(label: 'Oke', onPressed: () {}),
                  ),
              ],
              children: const [Text('Isi')],
            ),
          ),
        ),
      );
      final fade = tester.widget<EdgeFadeScroll>(find.byType(EdgeFadeScroll));
      // No button: runs to the edge. Button: 20pt fade above it.
      expect(
        fade.bottom,
        withButton ? EdgeFadeSide.standard : EdgeFadeSide.none,
      );
    });
  }
}
