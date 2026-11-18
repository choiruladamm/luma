/// App version in the backup manifest. Keep equal to `version` in pubspec.yaml
/// (a test checks it).
const appVersion = '0.3.0';

/// Contents of `manifest.json` in the backup file (docs/backup.md).
class BackupManifest {
  const BackupManifest({
    required this.appVersion,
    required this.schemaVersion,
    required this.createdAt,
    required this.books,
    required this.aiResults,
  });

  static const format = 'luma-backup';
  static const formatVersion = 1;

  final String appVersion;
  final int schemaVersion;
  final DateTime createdAt;
  final int books;
  final int aiResults;

  /// From `manifest.json`. A malformed shape → [FormatException].
  factory BackupManifest.fromJson(Object? json) {
    if (json is! Map ||
        json['format'] != format ||
        json['counts'] is! Map ||
        json['schemaVersion'] is! int) {
      throw const FormatException('not a Luma backup manifest');
    }
    final counts = json['counts'] as Map;
    final created = DateTime.tryParse('${json['createdAt']}');
    if (created == null) throw const FormatException('bad createdAt');
    return BackupManifest(
      appVersion: '${json['appVersion'] ?? '?'}',
      schemaVersion: json['schemaVersion'] as int,
      createdAt: created.toLocal(),
      books: (counts['books'] as num?)?.toInt() ?? 0,
      aiResults: (counts['aiResults'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, Object?> toJson() => {
    'format': format,
    'formatVersion': formatVersion,
    'appVersion': appVersion,
    'schemaVersion': schemaVersion,
    'createdAt': isoWithOffset(createdAt),
    'counts': {'books': books, 'aiResults': aiResults},
  };
}

/// The last backup the user successfully saved (Pengaturan).
typedef LastBackup = ({DateTime at, String name, int size});

/// `luma-backup-YYYYMMDD-HHmm.zip` (a plain zip: no custom file type needed).
String backupFileName(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'luma-backup-${t.year}${two(t.month)}${two(t.day)}'
      '-${two(t.hour)}${two(t.minute)}.zip';
}

/// ISO 8601 with the local timezone offset: `2026-10-06T21:30:00+07:00`.
String isoWithOffset(DateTime t) {
  String two(int n) => n.abs().toString().padLeft(2, '0');
  final o = t.timeZoneOffset;
  final sign = o.isNegative ? '-' : '+';
  return '${t.year}-${two(t.month)}-${two(t.day)}'
      'T${two(t.hour)}:${two(t.minute)}:${two(t.second)}'
      '$sign${two(o.inHours)}:${two(o.inMinutes % 60)}';
}

/// Days since the last backup when the reminder banner should show on the Rak,
/// null when it shouldn't (docs/backup.md). Counted in calendar days from the
/// last backup, or from the first book if never backed up (empty shelf = nothing
/// to protect). Shows from day 6 (before the 7-day reinstall cycle); dismissed
/// today → shows again tomorrow.
int? backupReminderDays({
  required DateTime now,
  DateTime? lastBackup,
  DateTime? firstBook,
  DateTime? dismissed,
}) {
  final since = lastBackup ?? firstBook;
  if (since == null) return null;
  DateTime day(DateTime t) => DateTime.utc(t.year, t.month, t.day);
  final days = day(now).difference(day(since)).inDays;
  if (days < backupReminderAfter) return null;
  if (dismissed != null && day(dismissed) == day(now)) return null;
  return days;
}

const backupReminderAfter = 6;
