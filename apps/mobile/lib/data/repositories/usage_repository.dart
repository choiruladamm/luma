import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/ai_reply.dart';
import '../database/app_database.dart';
import '../services/usage_service.dart';
import 'auth_repository.dart';
import 'settings_repository.dart';

/// Sends the daily usage rollup to the backend (docs/data-model.md, Storage
/// map): AI calls from `ai_calls` and reading time from `reading_sessions`,
/// per local day, feature, model, book, and key source.
///
/// Automatic, signed-in only, and independent of the sync toggle. Today is
/// sent the next day, once it is complete.
class UsageRepository {
  UsageRepository({
    required this._db,
    required this._service,
    required this._settings,
    required this._token,
    this._clock = DateTime.now,
  });

  final AppDatabase _db;
  final UsageService _service;
  final SettingsRepository _settings;
  final Future<String?> Function() _token;
  final DateTime Function() _clock;

  Future<bool>? _running;

  /// Open/resume trigger: at most one attempt per local day. Sends every
  /// unsent day up to yesterday and returns true when all of them arrived. A
  /// failure is silent and waits for a later day.
  Future<bool> sendIfDue() =>
      _running ??= _sendIfDue().whenComplete(() => _running = null);

  Future<bool> _sendIfDue() async {
    final now = _clock();
    final today = localDay(now);
    final yesterday = localDay(now.subtract(const Duration(days: 1)));
    final sent = await _settings.usageSentThrough();
    if (sent != null && sent.compareTo(yesterday) >= 0) return false;
    if (await _settings.usageAttemptedOn() == today) return false;
    final token = await _token();
    if (token == null) return false;
    await _settings.saveUsageAttemptedOn(today);
    try {
      final rows = await rollup(after: sent, through: yesterday);
      for (var i = 0; i < rows.length; i += UsageService.maxRows) {
        final end = (i + UsageService.maxRows).clamp(0, rows.length);
        await _service.send(token, rows.sublist(i, end));
        // Progress is saved per complete day, so a quota stop or a failure
        // resumes after it instead of resending the whole backlog.
        final last = rows[end - 1].day;
        if (end == rows.length || rows[end].day != last) {
          await _settings.saveUsageSentThrough(last);
        }
      }
      await _settings.saveUsageSentThrough(yesterday);
      return true;
    } on Object {
      return false;
    }
  }

  /// Rows for local days after [after] (all days when null) up to and
  /// including [through], ordered by day.
  Future<List<UsageRow>> rollup({
    String? after,
    required String through,
  }) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT day, feature, model, book_key, book_title, key_source, calls, failed,
        prompt_tokens, completion_tokens, cost_usd, reading_seconds FROM (
        SELECT date(c.created_at, 'unixepoch', 'localtime') AS day,
          c.kind AS feature, c.model AS model, $_bookKey AS book_key,
          b.title AS book_title, COALESCE(c.key_source, '') AS key_source,
          count(*) AS calls, sum(c.error IS NOT NULL) AS failed,
          COALESCE(sum(c.prompt_tokens), 0) AS prompt_tokens,
          COALESCE(sum(c.completion_tokens), 0) AS completion_tokens,
          sum(c.cost_usd) AS cost_usd, 0 AS reading_seconds
        FROM ai_calls c LEFT JOIN books b ON b.id = c.book_id
        GROUP BY 1, 2, 3, 4, 6
        UNION ALL
        SELECT date(s.started_at, 'unixepoch', 'localtime'), 'reading', '',
          $_bookKey, b.title, '', 0, 0, 0, 0, NULL, sum(s.seconds)
        FROM reading_sessions s JOIN books b ON b.id = s.book_id
        GROUP BY 1, 4
      )
      WHERE day > ?1 AND day <= ?2
      ORDER BY day
      ''',
          variables: [
            Variable.withString(after ?? ''),
            Variable.withString(through),
          ],
          readsFrom: {_db.aiCalls, _db.readingSessions, _db.books},
        )
        .get();
    return [
      for (final r in rows)
        UsageRow(
          day: r.read<String>('day'),
          feature: r.read<String>('feature'),
          model: r.read<String>('model'),
          bookKey: r.read<String>('book_key'),
          bookTitle: r.readNullable<String>('book_title'),
          keySource: AiKeySource.values
              .asNameMap()[r.read<String>('key_source')],
          calls: r.read<int>('calls'),
          failed: r.read<int>('failed'),
          promptTokens: r.read<int>('prompt_tokens'),
          completionTokens: r.read<int>('completion_tokens'),
          costUsd: r.readNullable<double>('cost_usd'),
          readingSeconds: r.read<int>('reading_seconds'),
        ),
    ];
  }

  // The book's sync wire key (docs/sync-protocol.md), stable across devices;
  // empty for a deleted book.
  static const _bookKey = "COALESCE('md:' || b.book_key, b.hash, '')";
}

/// [at] as a local `YYYY-MM-DD` day.
String localDay(DateTime at) {
  final d = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

final usageRepositoryProvider = Provider<UsageRepository>(
  (ref) => UsageRepository(
    db: ref.watch(appDatabaseProvider),
    service: ref.watch(usageServiceProvider),
    settings: ref.watch(settingsRepositoryProvider),
    token: ref.watch(authRepositoryProvider).token,
  ),
);
