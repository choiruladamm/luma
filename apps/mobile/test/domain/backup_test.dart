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

  group('backupReminderDays', () {
    final now = DateTime(2026, 10, 12, 9);

    test('from day 6 after the last backup', () {
      expect(
        backupReminderDays(now: now, lastBackup: DateTime(2026, 10, 7, 23)),
        isNull, // 5 days
      );
      expect(
        backupReminderDays(now: now, lastBackup: DateTime(2026, 10, 6, 23)),
        6,
      );
      expect(
        backupReminderDays(now: now, lastBackup: DateTime(2026, 9, 1)),
        41,
      );
    });

    test('never backed up: counts from the first book; empty shelf = none', () {
      expect(backupReminderDays(now: now), isNull);
      expect(
        backupReminderDays(now: now, firstBook: DateTime(2026, 10, 10)),
        isNull,
      );
      expect(
        backupReminderDays(now: now, firstBook: DateTime(2026, 10, 1)),
        11,
      );
    });

    test('the last backup wins over the first book', () {
      expect(
        backupReminderDays(
          now: now,
          lastBackup: DateTime(2026, 10, 11),
          firstBook: DateTime(2026, 1, 1),
        ),
        isNull,
      );
    });

    test('closed today: gone until tomorrow', () {
      final old = DateTime(2026, 9, 1);
      expect(
        backupReminderDays(
          now: now,
          lastBackup: old,
          dismissed: DateTime(2026, 10, 12, 8),
        ),
        isNull,
      );
      expect(
        backupReminderDays(
          now: now,
          lastBackup: old,
          dismissed: DateTime(2026, 10, 11, 23),
        ),
        41,
      );
    });
  });
}
