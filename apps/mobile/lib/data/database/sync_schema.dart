// Spec sync per kind (docs/backend.md, Sync antar device). Satu sumber buat
// trigger outbox, backfill migrasi 18, dan query data saat push: kunci alami
// dihitung SQL di sini, jadi repository gak perlu tahu.

/// Waktu sekarang dalam ms epoch (SQLite tanpa `unixepoch('subsec')`).
const sqlNowMs = "CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER)";

/// Kolom `DateTime` Drift (detik epoch) → ISO 8601 UTC, null tetap null.
String _iso(String col) => "strftime('%Y-%m-%dT%H:%M:%fZ', $col, 'unixepoch')";

String _bool(String col) => "json(CASE WHEN $col THEN 'true' ELSE 'false' END)";

/// Kunci buku: `md:{bookKey}` (Markdown) atau `hash` (EPUB/PDF).
String _bookKey(String r) => "COALESCE('md:' || $r.book_key, $r.hash)";

String _bookOf(String id) =>
    '(SELECT ${_bookKey('b')} FROM books b WHERE b.id = $id)';

/// `{bookKey}/{sortOrder}`; berlaku antar device cuma kalau `parserVersion` sama.
String _chapterOf(String id) =>
    "(SELECT ${_bookKey('b')} || '/' || c.sort_order FROM chapters c "
    'JOIN books b ON b.id = c.book_id WHERE c.id = $id)';

String _chatSessionOf(String id) =>
    "(SELECT ${_bookOf('s.book_id')} || '/' || (s.created_at * 1000) "
    'FROM chat_sessions s WHERE s.id = $id)';

String _parserOfBook(String id) =>
    '(SELECT parser_version FROM books WHERE id = $id)';

String _parserOfChapter(String id) =>
    '(SELECT b.parser_version FROM chapters c JOIN books b ON b.id = c.book_id '
    'WHERE c.id = $id)';

String _sortOrderOf(String id) =>
    '(SELECT sort_order FROM chapters WHERE id = $id)';

/// Setting yang ikut sync. Sisanya per device: `backup.*`, `catalog.*`,
/// riwayat Cari kata (kuncinya pakai ID buku lokal). Spec di file ini
/// tertanam di trigger yang udah kepasang di device: ubah = naikin schema,
/// `DROP TRIGGER` lalu `AppDatabase.createSyncTriggers` lagi di `onUpgrade`.
const syncedSettings = [
  'ai.model',
  'app.locale',
  'shelf.sort',
  'shelf.view',
  'theme',
  'reader.size',
  'reader.font',
  'reader.spacing',
  'reader.margin',
  'reader.hideStatusBar',
  'reader.showProgressLine',
  'reader.chatHintSeen',
];

/// Fase turn chat yang masih jalan; turn begini gak di-push.
const _runningPhases =
    "('preparing', 'retrieving', 'waiting', 'writing', 'slow')";

/// Upsert, bukan `INSERT OR REPLACE`: di dalam trigger, policy konflik
/// statement luar (upsert Drift `insertOnConflictUpdate`) menimpa `OR REPLACE`,
/// jadi tulisan kedua ke kunci yang sama gagal UNIQUE. Klausa upsert gak ikut
/// ditimpa.
const _upsert =
    'ON CONFLICT (kind, key) DO UPDATE SET updated_at = excluded.updated_at';

class SyncKind {
  const SyncKind({
    required this.name,
    required this.table,
    required this.key,
    required this.data,
    required this.backfillAt,
    this.when,
    this.tombstone = false,
  });

  /// Nama kind di server (`records.kind`).
  final String name;
  final String table;

  /// Ekspresi kunci alami untuk baris [r] (`NEW`, `OLD`, atau alias).
  final String Function(String r) key;

  /// `json_object(...)` data record dari baris alias `r`.
  final String data;

  /// Waktu ms dari isi baris buat backfill, supaya device yang migrasi
  /// belakangan gak ngalahin data yang beneran lebih baru di device lain.
  final String backfillAt;

  /// Syarat baris ikut sync (baris [r]).
  final String Function(String r)? when;

  /// Hapus dikirim sebagai tombstone. Cuma hapus yang dilakuin user (buku,
  /// sesi chat); hapus cascade anak gak dikirim (1 buku = ribuan tulis D1).
  final bool tombstone;

  String _keep(String r) => when == null ? '' : ' AND ${when!(r)}';

  /// Trigger insert/update (+ delete kalau [tombstone]) ke `sync_outbox`.
  /// Kunci dihitung saat kejadian: setelah baris dihapus ID lokalnya hilang.
  List<String> get triggers => [
    for (final (suffix, event, row) in [
      ('ai', 'INSERT', 'NEW'),
      ('au', 'UPDATE', 'NEW'),
      if (tombstone) ('ad', 'DELETE', 'OLD'),
    ])
      'CREATE TRIGGER IF NOT EXISTS sync_${table}_$suffix AFTER $event ON '
          '$table BEGIN INSERT INTO sync_outbox (kind, key, updated_at) '
          "SELECT '$name', k, $sqlNowMs FROM "
          '(SELECT ${key(row)} AS k) WHERE k IS NOT NULL${_keep(row)} '
          '$_upsert; END',
  ];

  /// Isi outbox dari baris yang udah ada (migrasi ke 18).
  String get backfill =>
      'INSERT INTO sync_outbox (kind, key, updated_at) '
      "SELECT '$name', ${key('r')}, $backfillAt FROM $table r "
      'WHERE ${key('r')} IS NOT NULL${_keep('r')} $_upsert';

  /// `(key, data)` buat kunci outbox kind ini (JSON array [keys]). Kunci yang
  /// barisnya udah gak ada gak muncul: tombstone atau dibuang.
  String get select =>
      'SELECT k AS key, data FROM (SELECT ${key('r')} AS k, $data AS data '
      'FROM $table r WHERE 1${_keep('r')}) '
      'WHERE k IN (SELECT value FROM json_each(?))';
}

final syncKinds = [
  SyncKind(
    name: 'book',
    table: 'books',
    key: _bookKey,
    tombstone: true,
    backfillAt: 'COALESCE(r.last_opened_at, r.created_at) * 1000',
    data:
        "json_object('sourceType', r.source_type, 'bookKey', r.book_key, "
        "'hash', r.hash, 'title', r.title, 'author', r.author, "
        "'fileName', r.file_name, 'coverName', r.cover_name, "
        "'originalTitle', r.original_title, 'originalAuthor', r.original_author, "
        "'useDefaultCover', ${_bool('r.use_default_cover')}, "
        "'sourceId', r.source_id, 'externalId', r.external_id, "
        "'parserVersion', r.parser_version, "
        "'contentRevision', r.content_revision, 'totalChars', r.total_chars, "
        "'createdAt', ${_iso('r.created_at')}, "
        "'lastOpenedAt', ${_iso('r.last_opened_at')}, "
        "'firstOpenedAt', ${_iso('r.first_opened_at')}, "
        "'readingSeconds', r.reading_seconds, "
        "'finishedAt', ${_iso('r.finished_at')})",
  ),
  SyncKind(
    name: 'reading_progress',
    table: 'reading_progress',
    key: (r) => _bookOf('$r.book_id'),
    backfillAt: 'r.updated_at * 1000',
    data:
        "json_object('parserVersion', ${_parserOfBook('r.book_id')}, "
        "'chapterSortOrder', ${_sortOrderOf('r.chapter_id')}, "
        "'paragraphIndex', r.paragraph_index, "
        "'paragraphOffset', r.paragraph_offset, "
        "'updatedAt', ${_iso('r.updated_at')})",
  ),
  SyncKind(
    name: 'reading_session',
    table: 'reading_sessions',
    key: (r) => "${_bookOf('$r.book_id')} || '/' || ($r.started_at * 1000)",
    backfillAt: '(r.started_at + r.seconds) * 1000',
    data:
        "json_object('parserVersion', ${_parserOfBook('r.book_id')}, "
        "'chapterSortOrder', ${_sortOrderOf('r.chapter_id')}, "
        "'startedAt', ${_iso('r.started_at')}, 'seconds', r.seconds, "
        "'startChar', r.start_char, 'endChar', r.end_char)",
  ),
  SyncKind(
    name: 'ai_result',
    table: 'ai_results',
    key: (r) => "${_chapterOf('$r.chapter_id')} || '/' || $r.group_index",
    backfillAt: 'COALESCE(r.last_opened_at, r.created_at) * 1000',
    data:
        "json_object('parserVersion', ${_parserOfChapter('r.chapter_id')}, "
        "'translations', r.translations, 'meaning', r.meaning, "
        "'model', r.model, 'promptVersion', r.prompt_version, "
        "'createdAt', ${_iso('r.created_at')}, 'openCount', r.open_count, "
        "'lastOpenedAt', ${_iso('r.last_opened_at')})",
  ),
  SyncKind(
    name: 'ai_breakdown',
    table: 'ai_breakdowns',
    key: (r) => "${_chapterOf('$r.chapter_id')} || '/' || $r.group_index",
    backfillAt: 'r.created_at * 1000',
    data:
        "json_object('parserVersion', ${_parserOfChapter('r.chapter_id')}, "
        "'body', r.body, 'sourceHash', r.source_hash, 'model', r.model, "
        "'promptVersion', r.prompt_version, "
        "'createdAt', ${_iso('r.created_at')})",
  ),
  SyncKind(
    name: 'setting',
    table: 'settings',
    key: (r) => '$r.key',
    when: (r) => "$r.key IN ('${syncedSettings.join("', '")}')",
    backfillAt: '0', // gak ada jejak waktu: kalah dari perubahan apa pun
    data: "json_object('value', r.value)",
  ),
  SyncKind(
    name: 'chat_session',
    table: 'chat_sessions',
    key: (r) => "${_bookOf('$r.book_id')} || '/' || ($r.created_at * 1000)",
    tombstone: true,
    backfillAt: 'r.updated_at * 1000',
    data:
        "json_object('contentRevision', r.content_revision, 'title', r.title, "
        "'manualTitle', ${_bool('r.manual_title')}, "
        "'createdAt', ${_iso('r.created_at')}, "
        "'updatedAt', ${_iso('r.updated_at')}, "
        "'lastOpenedAt', ${_iso('r.last_opened_at')})",
  ),
  SyncKind(
    name: 'chat_turn',
    table: 'chat_turns',
    key: (r) => "${_chatSessionOf('$r.session_id')} || '/' || $r.sequence",
    when: (r) => '$r.phase NOT IN $_runningPhases',
    backfillAt: 'r.updated_at * 1000',
    data:
        "json_object('sequence', r.sequence, 'question', r.question, "
        "'quote', r.quote, 'answer', r.answer, 'sources', r.sources, "
        "'exploration', r.exploration, 'steps', r.steps, 'phase', r.phase, "
        "'attempt', r.attempt, 'model', r.model, "
        "'promptVersion', r.prompt_version, 'error', r.error, "
        "'httpStatus', r.http_status, 'createdAt', ${_iso('r.created_at')}, "
        "'updatedAt', ${_iso('r.updated_at')})",
  ),
];

final syncKindsByName = {for (final k in syncKinds) k.name: k};
