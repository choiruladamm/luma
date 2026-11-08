// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get interfaceLanguage => 'Interface language';

  @override
  String get interfaceLanguageNote =>
      'This changes the interface language. Translations and AI responses stay in Indonesian.';

  @override
  String get languageSaveFailed => 'Couldn’t save the language. Try again.';
}
