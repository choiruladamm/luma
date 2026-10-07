/// "1.240" (titik ribuan).
String thousands(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');

/// "850 KB", "1,2 MB" (koma desimal).
String fileSize(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
  final mb = bytes / (1024 * 1024);
  return '${mb.toStringAsFixed(1).replaceAll('.', ',')} MB';
}

/// "hari ini", "kemarin", "3 hari lalu", "2 minggu lalu", "5 bulan lalu",
/// "1 tahun lalu", dihitung per tanggal kalender.
String ago(DateTime then, DateTime now) {
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(then.year, then.month, then.day)).inDays;
  if (days <= 0) return 'hari ini';
  if (days == 1) return 'kemarin';
  if (days < 7) return '$days hari lalu';
  if (days < 30) return '${days ~/ 7} minggu lalu';
  if (days < 365) return '${days ~/ 30} bulan lalu';
  return '${days ~/ 365} tahun lalu';
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', //
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

/// "3 Okt 2026, 21.40".
String dateTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.day} ${_months[t.month - 1]} ${t.year}, '
      '${two(t.hour)}.${two(t.minute)}';
}
