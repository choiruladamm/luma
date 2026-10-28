import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/chat_index_repository.dart';
import 'package:luma/domain/models/book.dart';
import 'package:luma/domain/models/book_chat.dart';

void main() {
  late AppDatabase db;
  late ChatIndexRepository repo;
  late ChatIndexKey key;
  Future<void> guard() async {}
  Float32List vector([double first = 0.125]) => Float32List(4096)..[0] = first;
  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    repo = ChatIndexRepository(db);
    final id = await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            sourceType: SourceType.epub,
            title: 'Book',
            parserVersion: 1,
            totalChars: 100,
          ),
        );
    key = (
      book: (bookId: id, contentRevision: 1),
      parserVersion: 1,
      chunkPolicyVersion: 1,
      embedding: ChatEmbeddingModel.qwen8b,
      queryTemplateVersion: 1,
    );
  });
  tearDown(() => db.close());

  test(
    'completed cache survives closing and reopening a real DB file',
    () async {
      final dir = await Directory.systemTemp.createTemp('luma-index-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/cache.sqlite');
      var disk = AppDatabase(NativeDatabase(file));
      final bookId = await disk
          .into(disk.books)
          .insert(
            BooksCompanion.insert(
              sourceType: SourceType.epub,
              title: 'Disk',
              parserVersion: 1,
              totalChars: 10,
            ),
          );
      final diskKey = (
        book: (bookId: bookId, contentRevision: 1),
        parserVersion: 1,
        chunkPolicyVersion: 1,
        embedding: ChatEmbeddingModel.qwen8b,
        queryTemplateVersion: 1,
      );
      var indexRepo = ChatIndexRepository(disk);
      final index = await indexRepo.load(diskKey, 'manifest', 1, guard);
      await indexRepo.saveBatch(index.id, 0, [vector()], 4096, guard);
      await disk.close();
      disk = AppDatabase(NativeDatabase(file));
      addTearDown(disk.close);
      indexRepo = ChatIndexRepository(disk);
      expect(
        (await indexRepo.load(diskKey, 'manifest', 1, guard)).vectors.single,
        vector(),
      );
    },
  );

  test(
    'batch durability, Float32 roundtrip and ready only after completion',
    () async {
      final index = await repo.load(key, 'manifest', 3, guard);
      await repo.saveBatch(index.id, 0, [vector(), vector(0.5)], 4096, guard);
      expect((await db.select(db.chatIndexes).getSingle()).ready, isFalse);
      repo = ChatIndexRepository(db);
      final resumed = await repo.load(key, 'manifest', 3, guard);
      expect(resumed.vectors.length, 2);
      expect(resumed.vectors.first, vector());
      await repo.saveBatch(index.id, 2, [vector(0.75)], 4096, guard);
      expect((await db.select(db.chatIndexes).getSingle()).ready, isTrue);
      expect((await repo.load(key, 'manifest', 3, guard)).vectors.length, 3);
      await expectLater(
        repo.saveBatch(index.id, 2, [vector()], 4096, guard),
        throwsA(anything),
      );
    },
  );

  test('out of order batch cannot mark an incomplete index ready', () async {
    final index = await repo.load(key, 'manifest', 2, guard);
    await expectLater(
      repo.saveBatch(index.id, 1, [vector()], 4096, guard),
      throwsFormatException,
    );
    expect(await db.select(db.chatVectors).get(), isEmpty);
    expect((await db.select(db.chatIndexes).getSingle()).ready, isFalse);
  });

  test('guard failure rolls back entire batch and ready marker', () async {
    final index = await repo.load(key, 'manifest', 2, guard);
    var calls = 0;
    await expectLater(
      repo.saveBatch(index.id, 0, [vector(), vector()], 4096, () async {
        if (++calls == 2) throw StateError('cancelled');
      }),
      throwsStateError,
    );
    expect(await db.select(db.chatVectors).get(), isEmpty);
    expect((await db.select(db.chatIndexes).getSingle()).ready, isFalse);
  });

  for (final corruption in ['checksum', 'dimension', 'nan', 'gap', 'missing']) {
    test(
      'rejects $corruption cache without using partial full-book index',
      () async {
        final index = await repo.load(key, 'manifest', 2, guard);
        await repo.saveBatch(index.id, 0, [vector(), vector()], 4096, guard);
        if (corruption == 'missing') {
          await (db.delete(
            db.chatVectors,
          )..where((v) => v.ordinal.equals(1))).go();
        } else if (corruption == 'gap') {
          await db.customStatement(
            'UPDATE chat_vectors SET ordinal = 5 WHERE ordinal = 1',
          );
        } else {
          final bytes = ByteData(corruption == 'dimension' ? 4 : 4096 * 4);
          bytes.setFloat32(
            0,
            corruption == 'nan' ? double.nan : 0.5,
            Endian.little,
          );
          final blob = bytes.buffer.asUint8List();
          await (db.update(
            db.chatVectors,
          )..where((v) => v.ordinal.equals(1))).write(
            ChatVectorsCompanion(
              vector: Value(blob),
              checksum: Value(
                corruption == 'checksum'
                    ? 'wrong'
                    : chatTextHash(base64Encode(blob)),
              ),
            ),
          );
        }
        expect((await repo.load(key, 'manifest', 2, guard)).vectors, isEmpty);
        expect((await db.select(db.chatIndexes).getSingle()).ready, isFalse);
      },
    );
  }

  test(
    'manifest replacement, model spaces and deletion preserve isolation',
    () async {
      final index = await repo.load(key, 'old', 1, guard);
      await repo.saveBatch(index.id, 0, [vector()], 4096, guard);
      final fallback = (
        book: key.book,
        parserVersion: 1,
        chunkPolicyVersion: 1,
        embedding: ChatEmbeddingModel.openaiLarge,
        queryTemplateVersion: 1,
      );
      await repo.load(fallback, 'old', 1, guard);
      expect((await repo.load(key, 'old', 1, guard)).vectors.length, 1);
      final replaced = await repo.load(key, 'new', 1, guard);
      expect(replaced.id, isNot(index.id));
      expect(replaced.vectors, isEmpty);
      expect(await db.select(db.chatVectors).get(), isEmpty);
      await db.contentChanged(key.book.bookId);
      expect(await db.select(db.chatIndexes).get(), isEmpty);
      await repo.load(key, 'new', 1, guard);
      await (db.delete(
        db.books,
      )..where((b) => b.id.equals(key.book.bookId))).go();
      expect(await db.select(db.chatIndexes).get(), isEmpty);
      expect(await db.select(db.chatVectors).get(), isEmpty);
    },
  );
}
