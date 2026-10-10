/// Versi app di manifest backup. Samain sama `version` di pubspec.yaml
/// (ada test yang ngecek).
const appVersion = '0.2.0';

/// Isi `manifest.json` di file backup (docs/backup.md).
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

  /// Dari `manifest.json`. Bentuknya salah → [FormatException].
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

/// Backup terakhir yang berhasil disimpen user (Pengaturan).
typedef LastBackup = ({DateTime at, String name, int size});

/// `luma-backup-YYYYMMDD-HHmm.zip` (zip biasa: gak perlu tipe file
/// custom).
String backupFileName(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'luma-backup-${t.year}${two(t.month)}${two(t.day)}'
      '-${two(t.hour)}${two(t.minute)}.zip';
}

/// ISO 8601 pake offset zona waktu lokal: `2026-10-06T21:30:00+07:00`.
String isoWithOffset(DateTime t) {
  String two(int n) => n.abs().toString().padLeft(2, '0');
  final o = t.timeZoneOffset;
  final sign = o.isNegative ? '-' : '+';
  return '${t.year}-${two(t.month)}-${two(t.day)}'
      'T${two(t.hour)}:${two(t.minute)}:${two(t.second)}'
      '$sign${two(o.inHours)}:${two(o.inMinutes % 60)}';
}

/// Berapa hari belum backup kalau banner pengingat perlu nongol di Rak, null
/// kalau gak perlu (docs/backup.md). Hitungan per tanggal kalender dari
/// backup terakhir, atau dari buku pertama kalau belum pernah backup (rak
/// kosong = gak ada yang perlu diamanin). Muncul mulai hari ke-6 (sebelum
/// siklus install ulang 7 hari); ditutup hari ini → nongol lagi besok.
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
