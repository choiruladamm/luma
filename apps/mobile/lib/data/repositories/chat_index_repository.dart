import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../domain/models/book_chat.dart';
import '../database/app_database.dart';

/// Durable document vectors only. Sources are rebuilt from validated book text.
class ChatIndexRepository {
  ChatIndexRepository(this.db);
  final AppDatabase db;

  String identity(ChatIndexKey key) => jsonEncode([
    1, // Little-endian Float32 storage format.
    key.book.bookId,
    key.book.contentRevision,
    key.parserVersion,
    key.chunkPolicyVersion,
    key.embedding.id,
    key.embedding.dimensions,
    key.queryTemplateVersion,
  ]);

  Future<({int id, List<Float32List> vectors})> load(
    ChatIndexKey key,
    String manifest,
    int count,
    Future<void> Function() guard,
  ) => db.transaction(() async {
    await guard();
    final name = identity(key);
    var row = await (db.select(
      db.chatIndexes,
    )..where((i) => i.identity.equals(name))).getSingleOrNull();
    if (row != null && (row.manifest != manifest || row.chunkCount != count)) {
      await (db.delete(
        db.chatIndexes,
      )..where((i) => i.id.equals(row!.id))).go();
      row = null;
    }
    final vectors = <Float32List>[];
    if (row != null) {
      final stored =
          await (db.select(db.chatVectors)
                ..where((v) => v.indexId.equals(row!.id))
                ..orderBy([(v) => OrderingTerm.asc(v.ordinal)]))
              .get();
      var valid = stored.length <= count;
      for (final v in stored) {
        if (v.ordinal != vectors.length ||
            v.vector.length != key.embedding.dimensions * 4 ||
            v.checksum != chatTextHash(base64Encode(v.vector))) {
          valid = false;
          break;
        }
        final bytes = ByteData.sublistView(v.vector);
        final vector = Float32List.fromList([
          for (var i = 0; i < key.embedding.dimensions; i++)
            bytes.getFloat32(i * 4, Endian.little),
        ]);
        if (vector.any((n) => !n.isFinite) || !vector.any((n) => n != 0)) {
          valid = false;
          break;
        }
        vectors.add(vector);
      }
      if (!valid || (row.ready && vectors.length != count)) {
        await (db.delete(
          db.chatVectors,
        )..where((v) => v.indexId.equals(row!.id))).go();
        vectors.clear();
        await (db.update(db.chatIndexes)..where((i) => i.id.equals(row!.id)))
            .write(const ChatIndexesCompanion(ready: Value(false)));
      }
    }
    final id =
        row?.id ??
        await db
            .into(db.chatIndexes)
            .insert(
              ChatIndexesCompanion.insert(
                bookId: key.book.bookId,
                identity: name,
                manifest: manifest,
                chunkCount: count,
              ),
            );
    if (vectors.length == count) {
      await (db.update(db.chatIndexes)..where((i) => i.id.equals(id))).write(
        const ChatIndexesCompanion(ready: Value(true)),
      );
    }
    await guard();
    return (id: id, vectors: vectors);
  });

  Future<void> saveBatch(
    int indexId,
    int start,
    List<Float32List> vectors,
    int dimensions,
    Future<void> Function() guard,
  ) => db.transaction(() async {
    await guard();
    final index = await (db.select(
      db.chatIndexes,
    )..where((i) => i.id.equals(indexId))).getSingle();
    final saved = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM chat_vectors WHERE index_id = ?',
          variables: [Variable(indexId)],
        )
        .getSingle();
    if (start != saved.read<int>('n') ||
        start < 0 ||
        vectors.isEmpty ||
        start + vectors.length > index.chunkCount) {
      throw const FormatException('Batch index tidak valid');
    }
    for (final (offset, vector) in vectors.indexed) {
      if (vector.length != dimensions ||
          vector.any((n) => !n.isFinite) ||
          !vector.any((n) => n != 0)) {
        throw const FormatException('Vektor index tidak valid');
      }
      final bytes = ByteData(dimensions * 4);
      for (var i = 0; i < dimensions; i++) {
        bytes.setFloat32(i * 4, vector[i], Endian.little);
      }
      final blob = bytes.buffer.asUint8List();
      await db
          .into(db.chatVectors)
          .insert(
            ChatVectorsCompanion.insert(
              indexId: indexId,
              ordinal: start + offset,
              vector: blob,
              checksum: chatTextHash(base64Encode(blob)),
            ),
          );
    }
    if (start + vectors.length == index.chunkCount) {
      await (db.update(db.chatIndexes)..where((i) => i.id.equals(indexId)))
          .write(const ChatIndexesCompanion(ready: Value(true)));
    }
    await guard();
  });
}
