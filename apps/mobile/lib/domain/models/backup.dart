/// Versi app di manifest backup. Samain sama `version` di pubspec.yaml
/// (ada test yang ngecek).
const appVersion = '0.1.0';

/// Isi `manifest.json` di file backup (docs bagian 10).
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

/// `luma-backup-YYYYMMDD-HHmm.zip` (zip biasa: iOS gak perlu tipe file
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
