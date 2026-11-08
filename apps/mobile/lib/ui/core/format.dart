import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';

String thousands(int n, {String locale = 'id'}) =>
    NumberFormat.decimalPattern(locale).format(n);

String fileSize(int bytes, {String locale = 'id'}) {
  if (bytes < 1024 * 1024) {
    return '${NumberFormat.decimalPattern(locale).format((bytes / 1024).ceil())} KB';
  }
  return '${NumberFormat('0.0', locale).format(bytes / (1024 * 1024))} MB';
}

/// Calendar boundaries, matching the existing relative-time behavior.
String ago(DateTime then, DateTime now, {String locale = 'id'}) {
  final l10n = lookupAppLocalizations(Locale(locale));
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(then.year, then.month, then.day)).inDays;
  if (days <= 0) return l10n.relativeToday;
  if (days == 1) return l10n.relativeYesterday;
  if (days < 7) return l10n.relativeDays(days);
  if (days < 30) return l10n.relativeWeeks(days ~/ 7);
  if (days < 365) return l10n.relativeMonths(days ~/ 30);
  return l10n.relativeYears(days ~/ 365);
}

String dateTime(DateTime t, {String locale = 'id'}) =>
    '${date(t, locale: locale)}, ${_time(t, locale)}';

String date(DateTime t, {String locale = 'id'}) =>
    DateFormat('d MMM y', locale).format(t);

String _time(DateTime t, String locale) =>
    DateFormat(locale == 'id' ? 'HH.mm' : 'HH:mm', locale).format(t);

String lastSeen(DateTime then, DateTime now, {String locale = 'id'}) {
  final day = ago(then, now, locale: locale);
  return '${day[0].toUpperCase()}${day.substring(1)}, ${_time(then, locale)}';
}

String formatReadingTime(int seconds, {String locale = 'id'}) {
  final minutes = seconds ~/ 60;
  final h = minutes ~/ 60, m = minutes % 60;
  final l10n = lookupAppLocalizations(Locale(locale));
  if (h == 0) return l10n.readingDurationMinutes(m);
  return l10n.readingDurationHours(h, m);
}
