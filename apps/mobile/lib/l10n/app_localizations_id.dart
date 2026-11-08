// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Indonesian (`id`).
class AppLocalizationsId extends AppLocalizations {
  AppLocalizationsId([String locale = 'id']) : super(locale);

  @override
  String get interfaceLanguage => 'Bahasa antarmuka';

  @override
  String get interfaceLanguageNote =>
      'Bahasa ini cuma buat tampilan. Terjemahan dan jawaban AI tetap Bahasa Indonesia.';

  @override
  String get languageSaveFailed => 'Bahasanya gagal disimpen. Coba lagi, ya.';
}
