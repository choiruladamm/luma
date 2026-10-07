import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ui/core/theme/stabilo_tokens.dart';
import 'package:luma/ui/features/bookshelf/views/shelf_header.dart';

void main() {
  // One "em" per size unit: the title is 6 wide per point of font size.
  double width(double size) => size * 6;

  ({double size, bool logo}) fit(double room, {double size = 28}) => fitTitle(
    room: room,
    size: size,
    floor: 22,
    logo: 28,
    logoGap: 8,
    titleWidth: width,
  );

  test('plenty of room: full size, with the logo', () {
    expect(fit(400), (size: 28.0, logo: true));
  });

  test('tight: the title shrinks first, down to 22, logo kept', () {
    // 28 needs 28 + 8 + 168 = 204. 24 needs 180. 22 needs 168.
    expect(fit(180), (size: 24.0, logo: true));
    expect(fit(168), (size: 22.0, logo: true));
  });

  test('still too tight at 22: the logo goes, the title stays at 22', () {
    expect(fit(150), (size: 22.0, logo: false));
    expect(fit(10), (size: 22.0, logo: false));
  });

  test('collapsed 17 is already under the floor: it never grows', () {
    expect(fit(400, size: 17), (size: 17.0, logo: true));
    expect(fit(60, size: 17), (size: 17.0, logo: false));
  });

  test('shelf columns: max(3, floor((width + 14) / 110))', () {
    // Width here is the content width: screen - 2 x 24.
    expect(Layout.shelfColumns(375 - 48), 3); // SE
    expect(Layout.shelfColumns(390 - 48), 3);
    expect(Layout.shelfColumns(430 - 48), 3); // Pro Max
    expect(Layout.shelfColumns(0), 3); // never under 3
    expect(Layout.shelfColumns(844 - 48), 7); // landscape
    expect(Layout.shelfColumns(820 - 48), 7); // iPad
    expect(Layout.shelfColumns(110 * 5 - 14), 5);
    expect(Layout.shelfColumns(110 * 5 - 15), 4);
  });
}
