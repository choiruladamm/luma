import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/models/backup.dart';

void main() {
  test('file name: luma-backup-YYYYMMDD-HHmm.zip', () {
    expect(
      backupFileName(DateTime(2026, 10, 6, 21, 30)),
      'luma-backup-20261006-2130.zip',
    );
    expect(
      backupFileName(DateTime(2026, 1, 2, 3, 4)),
      'luma-backup-20260102-0304.zip',
    );
  });

  test('createdAt carries the local offset', () {
    final t = DateTime(2026, 10, 6, 21, 30);
    final iso = isoWithOffset(t);
    expect(iso, startsWith('2026-10-06T21:30:00'));
    expect(DateTime.parse(iso).toUtc(), t.toUtc());
  });

  test('appVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*([^+\s]+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(appVersion, version);
  });
}
