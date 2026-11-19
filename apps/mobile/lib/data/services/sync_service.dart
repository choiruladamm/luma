import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backend_client.dart';

/// Represents a sync record (`POST /v2/sync/push`). A null [data] is a tombstone.
class SyncRecord {
  const SyncRecord({
    required this.kind,
    required this.key,
    required this.updatedAt,
    this.data,
  });

  final String kind;
  final String key;

  /// Device clock time of the change, in milliseconds since the epoch.
  final int updatedAt;
  final Map<String, Object?>? data;

  bool get deleted => data == null;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'key': key,
    'updated_at': DateTime.fromMillisecondsSinceEpoch(
      updatedAt,
      isUtc: true,
    ).toIso8601String(),
    'deleted': deleted,
    'data': data,
  };
}

/// Represents a record from `GET /v2/sync/pull`. A null [data] is a tombstone.
class PulledRecord {
  const PulledRecord({
    required this.kind,
    required this.key,
    required this.updatedAt,
    required this.schemaVersion,
    this.data,
  });

  factory PulledRecord.fromJson(Map<String, Object?> json) => PulledRecord(
    kind: json['kind']! as String,
    key: json['key']! as String,
    updatedAt: DateTime.parse(json['updated_at']! as String)
        .millisecondsSinceEpoch,
    schemaVersion: (json['schema_version']! as num).toInt(),
    data: (json['data'] as Map?)?.cast<String, Object?>(),
  );

  final String kind;
  final String key;

  /// Time of the change, in milliseconds since the epoch.
  final int updatedAt;
  final int schemaVersion;
  final Map<String, Object?>? data;

  bool get deleted => data == null;
}

/// A page of pulled records: `nextSeq` is the next cursor and `more` says whether records remain.
typedef PullPage = ({List<PulledRecord> records, int nextSeq, bool more});

/// Calls `/v2/sync/*` (docs/sync-protocol.md, Push and pull).
class SyncService {
  SyncService(this._client);

  final BackendClient _client;

  /// Maximum records the server accepts per push or pull page.
  static const maxRecords = 500;

  /// Maximum push body size; the server's limit is 1 MB, so this leaves room for the envelope.
  static const maxBytes = 900 * 1024;

  /// Returns records with `seq` greater than [since], up to [maxRecords] per page.
  Future<PullPage> pull(String token, int since) async {
    final res = await _client.request(
      'GET',
      '/sync/pull?since=$since&limit=$maxRecords',
      token: token,
    );
    final body = res.data!;
    return (
      records: [
        for (final r in body['records']! as List)
          PulledRecord.fromJson((r as Map).cast<String, Object?>()),
      ],
      nextSeq: (body['next_seq']! as num).toInt(),
      more: body['more']! as bool,
    );
  }

  /// Returns the server sequence after pushing and the number of records actually written.
  Future<({int seq, int applied})> push(
    String token,
    int schemaVersion,
    List<SyncRecord> records,
  ) async {
    final res = await _client.request(
      'POST',
      '/sync/push',
      token: token,
      body: {
        'schema_version': schemaVersion,
        'records': [for (final r in records) r.toJson()],
      },
    );
    return (
      seq: (res.data!['seq']! as num).toInt(),
      applied: (res.data!['applied']! as num).toInt(),
    );
  }
}

final syncServiceProvider = Provider<SyncService>(
  (ref) => SyncService(ref.watch(backendClientProvider)),
);
