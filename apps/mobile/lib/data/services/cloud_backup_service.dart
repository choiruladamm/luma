import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/backup.dart';
import 'backend_client.dart';

/// Represents a cloud database snapshot (`GET /v1/backups`).
class CloudBackup {
  const CloudBackup({
    required this.id,
    required this.createdAt,
    required this.size,
    required this.books,
    required this.aiResults,
    required this.schemaVersion,
    required this.appVersion,
  });

  factory CloudBackup.fromJson(Map<String, Object?> json) => CloudBackup(
    id: json['id']! as String,
    createdAt: DateTime.parse(json['createdAt']! as String).toLocal(),
    size: (json['size']! as num).toInt(),
    books: (json['books']! as num).toInt(),
    aiResults: (json['aiResults']! as num).toInt(),
    schemaVersion: (json['schemaVersion']! as num).toInt(),
    appVersion: json['appVersion']! as String,
  );

  final String id;
  final DateTime createdAt;
  final int size;
  final int books;
  final int aiResults;
  final int schemaVersion;
  final String appVersion;

  BackupManifest get manifest => BackupManifest(
    appVersion: appVersion,
    schemaVersion: schemaVersion,
    createdAt: createdAt,
    books: books,
    aiResults: aiResults,
  );
}

/// Calls `/v1/files/*` and `/v1/backups*` (docs/backend.md, Files and cloud backups).
///
/// The `STORAGE_FULL` error means the cloud quota is exhausted.
class CloudBackupService {
  CloudBackupService(this._client);

  final BackendClient _client;

  /// Maximum names the server accepts per `files/missing` call.
  static const missingBatch = 1000;

  Future<List<String>> missing(String token, List<String> names) async {
    final res = await _client.request(
      'POST',
      '/v1/files/missing',
      body: {'names': names},
      token: token,
    );
    return (res.data!['missing']! as List).cast<String>();
  }

  Future<void> uploadFile(
    String token,
    File file, {
    void Function(int sent, int total)? onProgress,
  }) => _client.upload(
    '/v1/files/${Uri.encodeComponent(file.uri.pathSegments.last)}',
    file,
    token: token,
    onProgress: onProgress,
  );

  /// Uploads [zip], which contains a manifest and `luma.sqlite`.
  ///
  /// The manifest is also sent in a header so listing snapshots need not open the zip.
  Future<CloudBackup> uploadSnapshot(
    String token,
    File zip,
    BackupManifest manifest, {
    void Function(int sent, int total)? onProgress,
  }) async => CloudBackup.fromJson(
    await _client.upload(
      '/v1/backups',
      zip,
      token: token,
      headers: {'x-backup-manifest': jsonEncode(manifest.toJson())},
      onProgress: onProgress,
    ),
  );

  /// Returns snapshots newest first.
  Future<List<CloudBackup>> list(String token) async {
    final res = await _client.request('GET', '/v1/backups', token: token);
    return [
      for (final b in res.data!['backups']! as List)
        CloudBackup.fromJson((b as Map).cast<String, Object?>()),
    ];
  }

  Future<void> downloadSnapshot(String token, String id, String savePath) =>
      _client.download('/v1/backups/$id', savePath, token: token);

  Future<void> downloadFile(String token, String name, String savePath) =>
      _client.download(
        '/v1/files/${Uri.encodeComponent(name)}',
        savePath,
        token: token,
      );
}

final cloudBackupServiceProvider = Provider<CloudBackupService>(
  (ref) => CloudBackupService(ref.watch(backendClientProvider)),
);
