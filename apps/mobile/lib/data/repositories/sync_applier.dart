import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/book_search.dart';
import '../database/app_database.dart';
import '../database/sync_schema.dart';
import '../services/file_storage.dart';
import '../services/sync_service.dart';

/// Hasil [SyncApplier.apply]: [held] = ditahan di `sync_inbox`.
typedef ApplyOutcome = ({int applied, int held});

/// Urutan nerapin dalam satu halaman: induk dulu (buku → sesi chat), anak
/// belakangan, biar turn gak nyangkut di inbox cuma karena sesinya belum ada.
const _order = [
  'setting',
  'book',
  'chat_session',
  'reading_progress',
  'reading_session',
  'ai_result',
  'ai_breakdown',
  'chat_turn',
];

/// Fase turn chat yang masih jalan di device ini: gak ditimpa pull.
const _runningPhases = {
  'preparing',
  'retrieving',
  'waiting',
  'writing',
  'slow',
};

/// Nerapin record pull ke tabel lokal (docs/backend.md, Sync antar device):
/// kunci alami → ID lokal, aturan merge sama dengan server, record yang
/// belum bisa diterapin ditahan di `sync_inbox`.
class SyncApplier {
  SyncApplier(this._db, this._files);

  final AppDatabase _db;
  final FileStorage _files;

  /// Terapin [records] dalam satu transaksi, plus simpan [cursor]
  /// (`sync.pullSeq`) di transaksi yang sama. Trigger outbox tetap nyala;
  /// baris outbox yang mereka tulis selama transaksi dihapus di akhir, jadi
  /// data pull gak di-push balik. Kecuali [_keep]: kunci yang hasil merge-nya
  /// beda dari server (data lokal ikut menang), itu memang harus di-push.
  Future<ApplyOutcome> apply(
    List<PulledRecord> records, {
    String? cursor,
  }) async {
    final deletedFiles = <({String? file, String? cover})>[];
    final outcome = await _db.transaction(() async {
      final start =
          (await _db.customSelect('SELECT $sqlNowMs AS t').getSingle())
              .read<int>('t');
      final keep = <(String, String)>{};
      var applied = 0;
      var held = 0;
      final sorted = [...records]
        ..sort((a, b) => _rank(a.kind).compareTo(_rank(b.kind)));
      for (final r in sorted) {
        final ok =
            r.schemaVersion <= _db.schemaVersion &&
            await _applyOne(r, keep, deletedFiles);
        if (ok) {
          applied++;
          await _dropInbox(r.kind, r.key);
        } else {
          held++;
          await _hold(r);
        }
      }
      if (cursor != null) {
        await _db
            .into(_db.settings)
            .insertOnConflictUpdate(
              SettingsCompanion.insert(key: pullCursorKey, value: cursor),
            );
      }
      await _db.customStatement(
        'DELETE FROM sync_outbox WHERE updated_at >= ? AND (kind, key) NOT IN '
        "(SELECT json_extract(value, '\$[0]'), json_extract(value, '\$[1]') "
        'FROM json_each(?))',
        [
          start,
          jsonEncode([
            for (final (k, key) in keep) [k, key],
          ]),
        ],
      );
      return (applied: applied, held: held);
    });
    for (final f in deletedFiles) {
      await _files.deleteBookFiles(fileName: f.file, coverName: f.cover);
    }
    // Tulisan SQL mentah gak keliatan stream Drift: kabarin biar Rak dkk.
    // ikut ke-refresh.
    if (outcome.applied > 0) _notify();
    return outcome;
  }

  void _notify() {
    final synced = {for (final k in syncKinds) k.table};
    _db.notifyUpdates({
      for (final t in _db.allTables)
        if (synced.contains(t.actualTableName)) TableUpdate.onTable(t),
    });
  }

  /// Buku Markdown dari dump cloud (`md-{bookKey}-{rev}.json.gz`, bentuk di
  /// `SyncRepository`): buku + bab + paragraf dengan `groupIndex` apa adanya,
  /// jadi kunci AI dari device lain langsung cocok. Metadata sisanya
  /// diterapin [retryInbox] dari record bukunya.
  Future<void> insertMarkdown(
    Map<String, Object?> dump,
    Map<String, Object?> book,
  ) async {
    await _db.transaction(() async {
      final bookId = await _db.customInsert(
        'INSERT INTO books (source_type, book_key, title, author, '
        'parser_version, content_revision, total_chars, created_at) '
        "VALUES ('markdown', ?, ?, ?, ?, ?, ?, ?)",
        variables: [
          Variable(dump['bookKey']! as String),
          Variable(book['title']! as String),
          Variable(book['author'] as String?),
          Variable(dump['parserVersion']! as int),
          Variable(dump['contentRevision']! as int),
          Variable(book['totalChars']! as int),
          Variable(_sec(book['createdAt']) ?? 0),
        ],
      );
      for (final c in dump['chapters']! as List) {
        final ch = (c as Map).cast<String, Object?>();
        final chapterId = await _db.customInsert(
          'INSERT INTO chapters (book_id, sort_order, chapter_number, title, '
          'section, char_offset) VALUES (?, ?, ?, ?, ?, ?)',
          variables: [
            Variable(bookId),
            Variable(ch['sortOrder']! as int),
            Variable(ch['chapterNumber'] as int?),
            Variable(ch['title']! as String),
            Variable(ch['section'] as String?),
            Variable(ch['charOffset']! as int),
          ],
        );
        for (final x in ch['paragraphs']! as List) {
          final [index, group, type, text] = x as List;
          await _db.customStatement(
            'INSERT INTO paragraphs (chapter_id, paragraph_index, group_index, '
            'type, text) VALUES (?, ?, ?, ?, ?)',
            [chapterId, index, group, type, text],
          );
        }
      }
    });
    _notify();
  }

  /// Coba lagi semua yang ditahan (abis pull, abis buku keimpor, abis update
  /// app). Yang tetap gak bisa, tetap di inbox.
  Future<ApplyOutcome> retryInbox() async =>
      apply(await _inbox(), cursor: null);

  /// Record buku di inbox yang bukunya belum ada di device: antrean download.
  Future<List<PulledRecord>> missingBooks() async => [
    for (final r in await _inbox())
      if (r.kind == 'book' && !r.deleted) r,
  ];

  Future<List<PulledRecord>> _inbox() async => [
    for (final r in await _db.select(_db.syncInbox).get())
      PulledRecord(
        kind: r.kind,
        key: r.key,
        updatedAt: r.updatedAt,
        schemaVersion: r.schemaVersion,
        data: r.data == null
            ? null
            : (jsonDecode(r.data!) as Map).cast<String, Object?>(),
      ),
  ];

  static int _rank(String kind) {
    final i = _order.indexOf(kind);
    return i < 0 ? _order.length : i;
  }

  /// true = selesai (diterapin, atau sengaja gak dipakai karena lokal
  /// menang); false = tahan di inbox.
  Future<bool> _applyOne(
    PulledRecord r,
    Set<(String, String)> keep,
    List<({String? file, String? cover})> deletedFiles,
  ) => switch (r.kind) {
    'book' => _book(r, keep, deletedFiles),
    'reading_progress' => _progress(r),
    'reading_session' => _readingSession(r),
    'ai_result' => _aiResult(r),
    'ai_breakdown' => _aiBreakdown(r),
    'setting' => _setting(r),
    'chat_session' => _chatSession(r),
    'chat_turn' => _chatTurn(r),
    _ => Future.value(true), // kind yang gak dikenal: buang
  };

  // ---------------------------------------------------------------- lookup

  Future<QueryRow?> _bookRow(String bookKey) => _db
      .customSelect(
        'SELECT * FROM books WHERE '
        "COALESCE('md:' || book_key, hash) = ?",
        variables: [Variable(bookKey)],
      )
      .getSingleOrNull();

  /// Bab buat record anak: cuma kalau buku ada dan `parserVersion` sama
  /// (nomor bab & grup cuma stabil dalam satu versi parser).
  Future<int?> _chapter(String bookKey, Map<String, Object?> d) async {
    final book = await _bookRow(bookKey);
    if (book == null) return null;
    if (book.read<int>('parser_version') != d['parserVersion']) return null;
    final sort = d['chapterSortOrder'];
    if (sort is! int) return null;
    final ch = await _db
        .customSelect(
          'SELECT id FROM chapters WHERE book_id = ? AND sort_order = ?',
          variables: [Variable(book.read<int>('id')), Variable(sort)],
        )
        .getSingleOrNull();
    return ch?.read<int>('id');
  }

  /// Bab dari kunci `{bookKey}/{sortOrder}/{groupIndex}` (hasil AI).
  Future<(int chapterId, int group)?> _aiChapter(
    String key,
    Map<String, Object?> d,
  ) async {
    final parts = _split(key, 2);
    if (parts == null) return null;
    final (bookKey, [sort, group]) = parts;
    final id = await _chapter(bookKey, {...d, 'chapterSortOrder': sort});
    return id == null ? null : (id, group);
  }

  /// `outbox` lokal punya perubahan buat kunci ini yang lebih baru dari
  /// record server: lokal menang, nanti di-push.
  Future<bool> _localNewer(PulledRecord r) async {
    final row = await _db
        .customSelect(
          'SELECT updated_at FROM sync_outbox WHERE kind = ? AND key = ?',
          variables: [Variable(r.kind), Variable(r.key)],
        )
        .getSingleOrNull();
    return row != null && row.read<int>('updated_at') > r.updatedAt;
  }

  // ----------------------------------------------------------------- kinds

  Future<bool> _book(
    PulledRecord r,
    Set<(String, String)> keep,
    List<({String? file, String? cover})> deletedFiles,
  ) async {
    final local = await _bookRow(r.key);
    if (r.deleted) {
      if (local != null) {
        final id = local.read<int>('id');
        await _db.customStatement('DELETE FROM books WHERE id = ?', [id]);
        await _db.customStatement('DELETE FROM settings WHERE key = ?', [
          bookSearchRecentKey(id),
        ]);
        deletedFiles.add((
          file: local.readNullable<String>('file_name'),
          cover: local.readNullable<String>('cover_name'),
        ));
      }
      // Anak buku ini yang masih nunggu gak bakal kepake lagi.
      await _db.customStatement(
        'DELETE FROM sync_inbox WHERE key = ? OR key LIKE ?',
        [r.key, '${r.key}/%'],
      );
      return true;
    }
    if (local == null) return false; // tunggu download + impor
    final d = r.data!;
    final localWins = await _localNewer(r);
    int? sec(String col) => local.readNullable<int>(col);
    final first = _min(sec('first_opened_at'), _sec(d['firstOpenedAt']));
    final finished = _min(sec('finished_at'), _sec(d['finishedAt']));
    final lastOpened = _max(sec('last_opened_at'), _sec(d['lastOpenedAt']));
    final seconds = _max(
      local.read<int>('reading_seconds'),
      d['readingSeconds'] as int?,
    );
    String? text(String col, String field) =>
        localWins ? local.readNullable<String>(col) : d[field] as String?;
    await _db.customStatement(
      'UPDATE books SET title = ?, author = ?, original_title = ?, '
      'original_author = ?, use_default_cover = ?, source_id = ?, '
      'external_id = ?, created_at = ?, first_opened_at = ?, finished_at = ?, '
      'last_opened_at = ?, reading_seconds = ? WHERE id = ?',
      [
        text('title', 'title') ?? local.read<String>('title'),
        text('author', 'author'),
        text('original_title', 'originalTitle'),
        text('original_author', 'originalAuthor'),
        if (localWins)
          local.read<int>('use_default_cover')
        else
          (d['useDefaultCover'] == true ? 1 : 0),
        text('source_id', 'sourceId'),
        text('external_id', 'externalId'),
        localWins
            ? local.read<int>('created_at')
            : _sec(d['createdAt']) ?? local.read<int>('created_at'),
        first,
        finished,
        lastOpened,
        seconds,
        local.read<int>('id'),
      ],
    );
    // Data lokal ikut nyumbang (lebih baru, dibuka lebih awal, waktu baca
    // lebih lama): server harus dapet hasil merge-nya.
    if (localWins ||
        first != _sec(d['firstOpenedAt']) ||
        finished != _sec(d['finishedAt']) ||
        lastOpened != _sec(d['lastOpenedAt']) ||
        seconds != d['readingSeconds']) {
      keep.add(('book', r.key));
    }
    return true;
  }

  Future<bool> _progress(PulledRecord r) async {
    final d = r.data;
    if (d == null) return true;
    final chapter = await _chapter(r.key, d);
    if (chapter == null) return false;
    if (await _localNewer(r)) return true;
    final book = (await _bookRow(r.key))!.read<int>('id');
    await _db.customStatement(
      'INSERT INTO reading_progress (book_id, chapter_id, paragraph_index, '
      'paragraph_offset, updated_at) VALUES (?, ?, ?, ?, ?) '
      'ON CONFLICT (book_id) DO UPDATE SET chapter_id = excluded.chapter_id, '
      'paragraph_index = excluded.paragraph_index, '
      'paragraph_offset = excluded.paragraph_offset, '
      'updated_at = excluded.updated_at',
      [
        book,
        chapter,
        d['paragraphIndex'],
        (d['paragraphOffset'] as num?)?.toDouble() ?? 0.0,
        _sec(d['updatedAt']) ?? r.updatedAt ~/ 1000,
      ],
    );
    return true;
  }

  Future<bool> _readingSession(PulledRecord r) async {
    final d = r.data;
    if (d == null) return true;
    final parts = _split(r.key, 1);
    if (parts == null) return true;
    final chapter = await _chapter(parts.$1, d);
    if (chapter == null) return false;
    final book = (await _bookRow(parts.$1))!.read<int>('id');
    final started = _sec(d['startedAt'])!;
    // Append-only: sesi yang udah ada (dari device ini) gak diubah.
    await _db.customStatement(
      'INSERT INTO reading_sessions (book_id, chapter_id, started_at, seconds, '
      'start_char, end_char) SELECT ?, ?, ?, ?, ?, ? WHERE NOT EXISTS '
      '(SELECT 1 FROM reading_sessions WHERE book_id = ? AND started_at = ?)',
      [
        book,
        chapter,
        started,
        d['seconds'],
        d['startChar'],
        d['endChar'],
        book,
        started,
      ],
    );
    return true;
  }

  /// `promptVersion` lebih tinggi menang, lalu `createdAt` terbaru.
  Future<bool> _remoteAiBetter(
    String table,
    (int, int) at,
    Map<String, Object?> d,
  ) async {
    final local = await _db
        .customSelect(
          'SELECT prompt_version, created_at FROM $table '
          'WHERE chapter_id = ? AND group_index = ?',
          variables: [Variable(at.$1), Variable(at.$2)],
        )
        .getSingleOrNull();
    if (local == null) return true;
    final pv = (d['promptVersion']! as int) - local.read<int>('prompt_version');
    if (pv != 0) return pv > 0;
    return (_sec(d['createdAt']) ?? 0) > local.read<int>('created_at');
  }

  Future<bool> _aiResult(PulledRecord r) async {
    final d = r.data;
    if (d == null) return true;
    final at = await _aiChapter(r.key, d);
    if (at == null) return false;
    if (!await _remoteAiBetter('ai_results', at, d)) return true;
    await _db.customStatement(
      'INSERT INTO ai_results (chapter_id, group_index, translations, meaning, '
      'model, prompt_version, created_at, open_count, last_opened_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (chapter_id, group_index) DO UPDATE SET '
      'translations = excluded.translations, meaning = excluded.meaning, '
      'model = excluded.model, prompt_version = excluded.prompt_version, '
      'created_at = excluded.created_at, open_count = excluded.open_count, '
      'last_opened_at = excluded.last_opened_at',
      [
        at.$1,
        at.$2,
        d['translations'],
        d['meaning'],
        d['model'],
        d['promptVersion'],
        _sec(d['createdAt']),
        d['openCount'] ?? 0,
        _sec(d['lastOpenedAt']),
      ],
    );
    return true;
  }

  Future<bool> _aiBreakdown(PulledRecord r) async {
    final d = r.data;
    if (d == null) return true;
    final at = await _aiChapter(r.key, d);
    if (at == null) return false;
    if (!await _remoteAiBetter('ai_breakdowns', at, d)) return true;
    await _db.customStatement(
      'INSERT INTO ai_breakdowns (chapter_id, group_index, body, source_hash, '
      'model, prompt_version, created_at) VALUES (?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (chapter_id, group_index) DO UPDATE SET '
      'body = excluded.body, source_hash = excluded.source_hash, '
      'model = excluded.model, prompt_version = excluded.prompt_version, '
      'created_at = excluded.created_at',
      [
        at.$1,
        at.$2,
        d['body'],
        d['sourceHash'],
        d['model'],
        d['promptVersion'],
        _sec(d['createdAt']),
      ],
    );
    return true;
  }

  Future<bool> _setting(PulledRecord r) async {
    final value = r.data?['value'];
    if (value is! String || !syncedSettings.contains(r.key)) return true;
    if (await _localNewer(r)) return true;
    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(key: r.key, value: value),
        );
    return true;
  }

  /// Sesi chat dari kunci `{bookKey}/{createdAt ms}`: (book id, created_at).
  Future<(int book, int created)?> _sessionRef(String key) async {
    final parts = _split(key, 1);
    if (parts == null) return null;
    final book = await _bookRow(parts.$1);
    if (book == null) return null;
    return (book.read<int>('id'), parts.$2.single ~/ 1000);
  }

  Future<int?> _sessionId(int book, int created) async =>
      (await _db
              .customSelect(
                'SELECT id FROM chat_sessions WHERE book_id = ? AND created_at = ?',
                variables: [Variable(book), Variable(created)],
              )
              .getSingleOrNull())
          ?.read<int>('id');

  Future<bool> _chatSession(PulledRecord r) async {
    final ref = await _sessionRef(r.key);
    if (ref == null) return r.deleted; // buku belum ada: tahan (kecuali hapus)
    final id = await _sessionId(ref.$1, ref.$2);
    if (r.deleted) {
      if (id != null) {
        await _db.customStatement('DELETE FROM chat_sessions WHERE id = ?', [
          id,
        ]);
      }
      return true;
    }
    if (await _localNewer(r)) return true;
    final d = r.data!;
    final values = [
      d['contentRevision'],
      d['title'],
      d['manualTitle'] == true ? 1 : 0,
      _sec(d['updatedAt']),
      _sec(d['lastOpenedAt']),
    ];
    if (id == null) {
      await _db.customStatement(
        'INSERT INTO chat_sessions (content_revision, title, manual_title, '
        'updated_at, last_opened_at, book_id, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [...values, ref.$1, ref.$2],
      );
    } else {
      await _db.customStatement(
        'UPDATE chat_sessions SET content_revision = ?, title = ?, '
        'manual_title = ?, updated_at = ?, last_opened_at = ? WHERE id = ?',
        [...values, id],
      );
    }
    return true;
  }

  Future<bool> _chatTurn(PulledRecord r) async {
    final d = r.data;
    if (d == null) return true;
    final parts = _split(r.key, 2);
    if (parts == null) return true;
    final (bookKey, [created, sequence]) = parts;
    final book = await _bookRow(bookKey);
    if (book == null) return false;
    final session = await _sessionId(book.read<int>('id'), created ~/ 1000);
    if (session == null) return false; // sesinya nyusul
    final local = await _db
        .customSelect(
          'SELECT phase FROM chat_turns WHERE session_id = ? AND sequence = ?',
          variables: [Variable(session), Variable(sequence)],
        )
        .getSingleOrNull();
    if (_runningPhases.contains(local?.read<String>('phase'))) return true;
    if (await _localNewer(r)) return true;
    await _db.customStatement(
      'INSERT INTO chat_turns (session_id, sequence, question, quote, answer, '
      'sources, exploration, steps, phase, attempt, model, prompt_version, '
      'error, http_status, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (session_id, sequence) DO UPDATE SET '
      'question = excluded.question, quote = excluded.quote, '
      'answer = excluded.answer, sources = excluded.sources, '
      'exploration = excluded.exploration, steps = excluded.steps, '
      'phase = excluded.phase, attempt = excluded.attempt, '
      'model = excluded.model, prompt_version = excluded.prompt_version, '
      'error = excluded.error, http_status = excluded.http_status, '
      'created_at = excluded.created_at, updated_at = excluded.updated_at',
      [
        session,
        sequence,
        d['question'],
        d['quote'],
        d['answer'],
        d['sources'] ?? '[]',
        d['exploration'],
        d['steps'],
        d['phase'],
        d['attempt'] ?? 1,
        d['model'],
        d['promptVersion'],
        d['error'],
        d['httpStatus'],
        _sec(d['createdAt']),
        _sec(d['updatedAt']),
      ],
    );
    return true;
  }

  // ----------------------------------------------------------------- inbox

  Future<void> _hold(PulledRecord r) => _db
      .into(_db.syncInbox)
      .insertOnConflictUpdate(
        SyncInboxCompanion.insert(
          kind: r.kind,
          key: r.key,
          data: Value(r.data == null ? null : jsonEncode(r.data)),
          updatedAt: r.updatedAt,
          schemaVersion: r.schemaVersion,
        ),
      );

  Future<void> _dropInbox(String kind, String key) => (_db.delete(
    _db.syncInbox,
  )..where((i) => i.kind.equals(kind) & i.key.equals(key))).go();
}

/// Kunci cursor pull di `settings` (gak ikut sync): `{userId}:{seq}`.
const pullCursorKey = 'sync.pullSeq';

/// Pecah kunci jadi (kunci buku, [numbers] angka terakhir), dari kanan:
/// kunci buku Markdown bisa aja ngandung `/`.
(String, List<int>)? _split(String key, int numbers) {
  final parts = key.split('/');
  if (parts.length <= numbers) return null;
  final tail = [
    for (final s in parts.sublist(parts.length - numbers)) int.tryParse(s),
  ];
  if (tail.contains(null)) return null;
  return (parts.sublist(0, parts.length - numbers).join('/'), tail.cast<int>());
}

/// ISO 8601 → detik epoch (format kolom `DateTime` Drift).
int? _sec(Object? iso) =>
    iso is String ? DateTime.parse(iso).millisecondsSinceEpoch ~/ 1000 : null;

int? _min(int? a, int? b) => a == null ? b : (b == null || a <= b ? a : b);
int? _max(int? a, int? b) => a == null ? b : (b == null || a >= b ? a : b);

final syncApplierProvider = Provider<SyncApplier>(
  (ref) => SyncApplier(
    ref.watch(appDatabaseProvider),
    ref.watch(fileStorageProvider),
  ),
);
