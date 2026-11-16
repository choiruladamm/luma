import 'package:crypto/crypto.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma/l10n/app_localizations_en.dart';
import 'package:luma/l10n/app_localizations_id.dart';
import 'package:luma/domain/models/book.dart';
import 'package:luma/ui/core/book_copy.dart';

void main() {
  test('ID and EN have identical keys and all placeholders are translated', () {
    Map<String, dynamic> arb(String language) =>
        jsonDecode(File('lib/l10n/app_$language.arb').readAsStringSync())
            as Map<String, dynamic>;
    final id = arb('id'), en = arb('en');
    final keys = id.keys.where((key) => !key.startsWith('@')).toSet();
    expect(en.keys.where((key) => !key.startsWith('@')).toSet(), keys);
    for (final key in keys) {
      expect(en[key], isNotEmpty, reason: key);
      final parameters = (id['@$key']?['placeholders'] as Map?)?.keys ?? [];
      for (final parameter in parameters) {
        expect(en[key], contains('{$parameter'), reason: '$key: $parameter');
      }
    }
    expect(jsonDecode(File('untranslated.json').readAsStringSync()), isEmpty);
  });

  test(
    'English count labels pluralize and model labels use the requested locale',
    () {
      final en = AppLocalizationsEn(), id = AppLocalizationsId();
      expect(en.chapterCount(0), '0 chapters');
      expect(en.chapterCount(1), '1 chapter');
      expect(en.chapterCount(2), '2 chapters');
      expect(ShelfSort.title.label(en), 'Title (A–Z)');
      expect(ShelfSort.title.label(id), 'Judul (A–Z)');
      expect(localizedChapterRanges([1, 2, 3], en), 'Chapters 1–3');
    },
  );

  test('frozen AI runtime dependencies differ only in two localization dependency roles', () {
    final current = File('pubspec.lock').readAsStringSync();
    var normalized = current;
    for (final package in ['flutter_localizations', 'intl']) {
      final role = RegExp(
        '(^  $package:\\n    dependency: )"direct main"',
        multiLine: true,
      );
      expect(role.allMatches(normalized), hasLength(1));
      normalized = normalized.replaceFirstMapped(
        role,
        (m) => '${m[1]}transitive',
      );
    }
    // Dibekukan ulang 14 Nov 2026 (google_sign_in). Alasan & daftar:
    // docs/llm-evals.md (Pembekuan ulang guard).
    expect(
      sha256.convert(utf8.encode(normalized)).toString(),
      '02d79191e3372cc885440884a362a07615d143062216c86c935428611fb492c7',
    );
  });
}
