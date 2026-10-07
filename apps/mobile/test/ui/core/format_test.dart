import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ui/core/format.dart';

void main() {
  test('thousands', () {
    expect(thousands(0), '0');
    expect(thousands(999), '999');
    expect(thousands(1240), '1.240');
    expect(thousands(1234567), '1.234.567');
  });

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

  test('dateTime', () {
    expect(dateTime(DateTime(2026, 10, 3, 21, 40)), '3 Okt 2026, 21.40');
    expect(dateTime(DateTime(2026, 1, 9, 7, 5)), '9 Jan 2026, 07.05');
  });

  test('date', () {
    expect(date(DateTime(2026, 9, 12, 23, 59)), '12 Sep 2026');
    expect(date(DateTime(2026, 1, 9)), '9 Jan 2026');
  });

  test('lastSeen: capitalised day + time', () {
    final now = DateTime(2026, 10, 7, 9);
    expect(lastSeen(DateTime(2026, 10, 6, 22, 14), now), 'Kemarin, 22.14');
    expect(lastSeen(DateTime(2026, 10, 7, 8, 5), now), 'Hari ini, 08.05');
    expect(lastSeen(DateTime(2026, 10, 2, 21, 40), now), '5 hari lalu, 21.40');
  });
}
