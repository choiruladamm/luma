import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backend_client.dart';

/// Satu record sync (`POST /v1/sync/push`). [data] null = tombstone.
class SyncRecord {
  const SyncRecord({
    required this.kind,
    required this.key,
    required this.updatedAt,
    this.data,
  });

  final String kind;
  final String key;

  /// ms epoch, jam device saat perubahan.
  final int updatedAt;
  final Map<String, Object?>? data;

  bool get deleted => data == null;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'key': key,
    'updatedAt': DateTime.fromMillisecondsSinceEpoch(
      updatedAt,
      isUtc: true,
    ).toIso8601String(),
    'deleted': deleted,
    'data': data,
  };
}

/// Satu record dari `GET /v1/sync/pull`. [data] null = tombstone.
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
    updatedAt: DateTime.parse(json['updatedAt']! as String)
        .millisecondsSinceEpoch,
    schemaVersion: (json['schemaVersion']! as num).toInt(),
    data: (json['data'] as Map?)?.cast<String, Object?>(),
  );

  final String kind;
  final String key;

  /// ms epoch.
  final int updatedAt;
  final int schemaVersion;
  final Map<String, Object?>? data;

  bool get deleted => data == null;
}

/// Satu halaman pull: [nextSeq] = cursor berikutnya, [more] = masih ada.
typedef PullPage = ({List<PulledRecord> records, int nextSeq, bool more});

/// Panggilan `/v1/sync/*` (docs/backend.md, Sync antar device).
class SyncService {
  SyncService(this._client);

  final BackendClient _client;

  /// Batas server per push / halaman pull.
  static const maxRecords = 500;

  /// Body maks server 1MB; sisain ruang buat envelope.
  static const maxBytes = 900 * 1024;

  /// Record dengan `seq` > [since], maks [maxRecords] per halaman.
  Future<PullPage> pull(String token, int since) async {
    final res = await _client.request(
      'GET',
      '/v1/sync/pull?since=$since&limit=$maxRecords',
      token: token,
    );
    final body = res.data!;
    return (
      records: [
        for (final r in body['records']! as List)
          PulledRecord.fromJson((r as Map).cast<String, Object?>()),
      ],
      nextSeq: (body['nextSeq']! as num).toInt(),
      more: body['more']! as bool,
    );
  }

  /// `seq` server setelah push + jumlah record yang beneran ditulis.
  Future<({int seq, int applied})> push(
    String token,
    int schemaVersion,
    List<SyncRecord> records,
  ) async {
    final res = await _client.request(
      'POST',
      '/v1/sync/push',
      token: token,
      body: {
        'schemaVersion': schemaVersion,
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
