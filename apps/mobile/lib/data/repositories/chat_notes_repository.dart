import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/chat_exploration.dart';
import '../../domain/models/book_chat.dart';
import '../database/app_database.dart';

/// Catatan per bab untuk pertanyaan seluruh buku (#151). Kunci: buku +
/// revision + bab + manifest window bab + policy. Hanya ditulis setelah bab
/// itu selesai dibaca dan tervalidasi; dibaca saat send eksplisit berikutnya.
class ChatNotesRepository {
  ChatNotesRepository(this.db);
  final AppDatabase db;

  /// Catatan bab yang masih cocok dengan [manifests] (chapterId → manifest).
  Future<Map<int, List<ChatCachedNote>>> load(
    ChatBookRef book,
    Map<int, String> manifests,
  ) async {
    if (manifests.isEmpty) return const {};
    final rows =
        await (db.select(db.chatChapterNotes)..where(
              (n) =>
                  n.bookId.equals(book.bookId) &
                  n.contentRevision.equals(book.contentRevision) &
                  n.policy.equals(chatChapterNotesPolicy) &
                  n.chapterId.isIn(manifests.keys),
            ))
            .get();
    final result = <int, List<ChatCachedNote>>{};
    for (final row in rows) {
      if (row.manifest != manifests[row.chapterId]) continue;
      try {
        result[row.chapterId] = decodeChatCachedNotes(row.notes);
      } on FormatException {
        continue; // Baris rusak diabaikan; bab dibaca ulang dan ditimpa.
      }
    }
    return result;
  }

  /// Simpan/timpa catatan satu bab. Transaksi pendek, di luar network.
  Future<void> save(
    ChatBookRef book, {
    required int chapterId,
    required String manifest,
    required String model,
    required List<ChatCachedNote> notes,
  }) => db.transaction(() async {
    final b = await (db.select(
      db.books,
    )..where((b) => b.id.equals(book.bookId))).getSingleOrNull();
    if (b == null || b.contentRevision != book.contentRevision) return;
    await (db.delete(db.chatChapterNotes)..where(
          (n) =>
              n.chapterId.equals(chapterId) &
              n.policy.equals(chatChapterNotesPolicy),
        ))
        .go();
    await db
        .into(db.chatChapterNotes)
        .insert(
          ChatChapterNotesCompanion.insert(
            bookId: book.bookId,
            contentRevision: book.contentRevision,
            chapterId: chapterId,
            manifest: manifest,
            policy: chatChapterNotesPolicy,
            model: model,
            notes: jsonEncode(encodeChatCachedNotes(notes)),
          ),
        );
  });

  Future<int> count(int bookId) async => (await (db.select(
    db.chatChapterNotes,
  )..where((n) => n.bookId.equals(bookId))).get()).length;
}
