import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';

/// Isi cache terjemahan buat Pengaturan.
typedef AiCacheStats = ({int paragraphs, int bytes});

/// Cache hasil LLM (`ai_results`).
class AiResultsRepository {
  AiResultsRepository(this._db);

  final AppDatabase _db;

  /// Paragraf yang udah ada terjemahannya + kira-kira ukuran teksnya.
  Stream<AiCacheStats> watchStats() => _db
      .customSelect(
        'SELECT '
        '(SELECT COUNT(*) FROM paragraphs p JOIN ai_results a '
        'ON a.chapter_id = p.chapter_id AND a.group_index = p.group_index) '
        'AS n, '
        '(SELECT COALESCE(SUM(LENGTH(CAST(translations AS BLOB)) + '
        'LENGTH(CAST(meaning AS BLOB))), 0) FROM ai_results) AS bytes',
        readsFrom: {_db.paragraphs, _db.aiResults},
      )
      .watchSingle()
      .map((r) => (paragraphs: r.read<int>('n'), bytes: r.read<int>('bytes')));

  /// Hapus semua terjemahan; grup yang dibuka lagi bakal manggil LLM ulang.
  Future<void> clear() => _db.delete(_db.aiResults).go();
}

final aiResultsRepositoryProvider = Provider<AiResultsRepository>(
  (ref) => AiResultsRepository(ref.watch(appDatabaseProvider)),
);

final aiCacheStatsProvider = StreamProvider.autoDispose<AiCacheStats>(
  (ref) => ref.watch(aiResultsRepositoryProvider).watchStats(),
);
