// Per-kind sync spec (docs/sync-protocol.md, Records and keys). It is the
// single source for the outbox triggers, the schema 18 migration backfill, and
// the data query at push time: natural keys are computed in SQL here, so the
// repository doesn't need to know them.

/// The current time in epoch milliseconds, computed without `unixepoch('subsec')`, which SQLite lacks here.
const sqlNowMs = "CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER)";

/// Converts a Drift `DateTime` column (epoch seconds) to ISO 8601 UTC; null stays null.
String _iso(String col) => "strftime('%Y-%m-%dT%H:%M:%fZ', $col, 'unixepoch')";

String _bool(String col) => "json(CASE WHEN $col THEN 'true' ELSE 'false' END)";

/// Returns the book key: `md:{bookKey}` for Markdown, or `hash` for EPUB and PDF.
String _bookKey(String r) => "COALESCE('md:' || $r.book_key, $r.hash)";

String _bookOf(String id) =>
    '(SELECT ${_bookKey('b')} FROM books b WHERE b.id = $id)';

/// Returns `{bookKey}/{sortOrder}`, which identifies the same chapter across devices only if `parserVersion` matches.
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

/// The settings that sync; the rest stay per device: `backup.*`, `catalog.*`,
/// and the Cari kata history (its key uses the local book id).
///
/// This spec is baked into the triggers already installed on devices, so a
/// change needs a schema bump that runs `DROP TRIGGER` and then
/// `AppDatabase.createSyncTriggers` again in `onUpgrade`.
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

/// Chat turn phases that are still running; such turns are not pushed.
const _runningPhases =
    "('preparing', 'retrieving', 'waiting', 'writing', 'slow')";

/// An upsert rather than `INSERT OR REPLACE`: inside a trigger, the conflict
/// policy of the outer statement (Drift's `insertOnConflictUpdate` upsert)
/// overrides `OR REPLACE`, so a second write to the same key fails UNIQUE. An
/// upsert clause isn't overridden.
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

  /// The kind name on the server (`records.kind`).
  final String name;
  final String table;

  /// Builds the natural-key expression for row `r` (`NEW`, `OLD`, or an alias).
  final String Function(String r) key;

  /// The `json_object(...)` expression for the record data of the row aliased `r`.
  final String data;

  /// The backfill timestamp in milliseconds, derived from the row content, so
  /// a device that migrates later doesn't beat data that is genuinely newer on
  /// another device.
  final String backfillAt;

  /// Builds the condition for row `r` to be synced.
  final String Function(String r)? when;

  /// Whether a delete is sent as a tombstone.
  ///
  /// Only deletes the user performs (a book, a chat session) are sent;
  /// cascaded child deletes aren't, since one book would cost thousands of D1
  /// writes.
  final bool tombstone;

  String _keep(String r) => when == null ? '' : ' AND ${when!(r)}';

  /// The insert and update triggers (plus delete when [tombstone] is true)
  /// that write to `sync_outbox`.
  ///
  /// The key is computed at event time because the local id is gone once the
  /// row is deleted.
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

  /// Fills the outbox from existing rows (the schema 18 migration).
  String get backfill =>
      'INSERT INTO sync_outbox (kind, key, updated_at) '
      "SELECT '$name', ${key('r')}, $backfillAt FROM $table r "
      'WHERE ${key('r')} IS NOT NULL${_keep('r')} $_upsert';

  /// Selects `(key, data)` for the outbox keys of this kind, passed as a JSON
  /// array.
  ///
  /// A key whose row is gone doesn't appear: it is a tombstone or is
  /// dropped.
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
    backfillAt: '0', // No timestamp trace exists, so any other change wins.
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
