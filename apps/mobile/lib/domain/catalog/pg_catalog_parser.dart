import 'dart:convert';
import 'dart:typed_data';

import 'catalog_row.dart';

/// Kolom `pg_catalog.csv`, urutannya tetap:
/// `Text#,Type,Issued,Title,Language,Authors,Subjects,LoCC,Bookshelves`.
const _columns = 9;

/// CSV (udah di-gunzip) → baris teks Inggris. Baris rusak (kolom kurang, id
/// bukan angka) dilewatin. Pure, aman dipanggil dari `Isolate.run`.
List<CatalogRow> parsePgCatalog(Uint8List csv) {
  final records = _parseCsv(utf8.decode(csv, allowMalformed: true));
  final rows = <CatalogRow>[];
  for (final r in records.skip(1)) {
    if (r.length < _columns) continue;
    final id = int.tryParse(r[0]);
    if (id == null || r[1] != 'Text' || r[4] != 'en') continue;
    rows.add(
      CatalogRow(
        id: id,
        title: r[3].trim(),
        authors: parseAuthors(r[5]),
        subjects: splitList(r[6]),
        bookshelves: splitList(r[8]),
        issued: r[2].isEmpty ? null : r[2],
      ),
    );
  }
  return rows;
}

/// `Austen, Jane, 1775-1817; Leech, John, 1817-1864 [Illustrator]`. Peran
/// dalam `[...]` dibuang, orangnya tetep. Tahun = bagian terakhir setelah
/// koma yang bentuknya `1775-1817` / `1900-` / `-1468`, tanda `?` diabaikan.
List<CatalogAuthor> parseAuthors(String field) => [
  for (final part in field.split(';'))
    if (part.replaceAll(_role, '').trim() case final s when s.isNotEmpty)
      _author(s),
];

final _role = RegExp(r'\s*\[[^\]]*\]');
final _years = RegExp(r'^(\d{1,4})?\??-(\d{1,4})?\??$');

CatalogAuthor _author(String s) {
  final comma = s.lastIndexOf(',');
  if (comma > 0) {
    final m = _years.firstMatch(s.substring(comma + 1).trim());
    if (m != null) {
      return CatalogAuthor(
        s.substring(0, comma).trim(),
        birth: int.tryParse(m[1] ?? ''),
        death: int.tryParse(m[2] ?? ''),
      );
    }
  }
  return CatalogAuthor(s);
}

/// `a; b; ` → `[a, b]`.
List<String> splitList(String field) => [
  for (final s in field.split(';'))
    if (s.trim() case final t when t.isNotEmpty) t,
];

/// Parser CSV RFC 4180: quote `"`, escape `""`, koma + newline di dalam quote.
/// Baris kosong dilewatin.
List<List<String>> _parseCsv(String text) {
  final records = <List<String>>[];
  var fields = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var i = 0;
  while (i < text.length) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      fields.add(field.toString());
      field.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      fields.add(field.toString());
      field.clear();
      if (fields.length > 1 || fields.first.isNotEmpty) records.add(fields);
      fields = <String>[];
    } else {
      field.write(c);
    }
    i++;
  }
  if (field.isNotEmpty || fields.isNotEmpty) {
    fields.add(field.toString());
    records.add(fields);
  }
  return records;
}
