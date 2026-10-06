import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ui/core/format.dart';

void main() {
  test('fileSize', () {
    expect(fileSize(85 * 1024), '85 KB');
    expect(fileSize(1), '1 KB');
    expect(fileSize((1.2 * 1024 * 1024).round()), '1,2 MB');
  });

  test('ago counts calendar days', () {
    final now = DateTime(2026, 10, 7, 9);
    expect(ago(DateTime(2026, 10, 7, 1), now), 'hari ini');
    expect(ago(DateTime(2026, 10, 6, 23), now), 'kemarin');
    expect(ago(DateTime(2026, 10, 2), now), '5 hari lalu');
    expect(ago(DateTime(2026, 9, 23), now), '2 minggu lalu');
    expect(ago(DateTime(2026, 5, 1), now), '5 bulan lalu');
    expect(ago(DateTime(2024, 10, 1), now), '2 tahun lalu');
  });
}
